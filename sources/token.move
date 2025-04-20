module iota_test::testi_token {
    use iota::coin::{Self, TreasuryCap};
    use iota::table::{Self, Table};
    use iota::event::Self;

    const EClaim: u64 = 0;
    const EMint: u64 = 1;

    const INITIAL_SUPPLY: u64 = 1000;
    const MAX_SUPPLY: u64 = 100_000_000;
    const CLAIMABLE: u64 = 100;

    public struct TESTI_TOKEN has drop {}
    public struct TestEventSharedObj has copy, drop { addr_obj: address }
    public struct TestEventMint has copy, drop { total_supply: u64 }

    public struct TestEventTransfer has copy, drop {
        from: address,
        to: address,
        amount: u64
    }

    public struct ClaimTracker has key {
        id: UID,
        treasury_cap: TreasuryCap<TESTI_TOKEN>,
        claimed: Table<address, bool>
    }

    public fun maximum_supply(): u64 {
        MAX_SUPPLY
    }

    public fun total_supply(tracker: &ClaimTracker): u64 {
        coin::total_supply(&tracker.treasury_cap)
    }

    public fun remaining_supply(tracker: &ClaimTracker): u64 {
        MAX_SUPPLY - total_supply(tracker)
    }

    public fun total_claimed(tracker: &ClaimTracker): u64 {
        table::length(&tracker.claimed)
    }

    fun init(w: TESTI_TOKEN, ctx: &mut TxContext) {
        let (mut cap, metacap) = coin::create_currency(
            w,
            6, 
            b"TESTI", 
            b"Testi Token", 
            b"100M Max supply with free claim", 
            option::none(), 
            ctx
        );

        transfer::public_freeze_object(metacap);
    
        cap.mint_and_transfer(INITIAL_SUPPLY, ctx.sender(), ctx);
        event::emit(TestEventTransfer { from: @iota_test, to: ctx.sender(), amount: INITIAL_SUPPLY });

        let tracker_uid = object::new(ctx);
        let tracker_addr = object::uid_to_address(&tracker_uid);

        transfer::share_object(ClaimTracker {
            id: tracker_uid,
            treasury_cap: cap,
            claimed: table::new(ctx)
        });
        
        event::emit(TestEventSharedObj { addr_obj: tracker_addr });
    }

    fun mint(tracker: &mut ClaimTracker, amount: u64, ctx: &mut TxContext) {
        assert!(total_supply(tracker) + amount <= MAX_SUPPLY, EMint);

        coin::mint_and_transfer(
            &mut tracker.treasury_cap,
            amount,
            ctx.sender(),
            ctx
        );

        event::emit(TestEventMint { total_supply: total_supply(tracker)  });
    }

    public fun claim(tracker: &mut ClaimTracker, ctx: &mut TxContext) {
        assert!(!table::contains(&tracker.claimed, ctx.sender()), EClaim);

        table::add(&mut tracker.claimed, ctx.sender(), true);

        mint(tracker, CLAIMABLE, ctx);

        event::emit(TestEventTransfer { from: @iota_test, to: ctx.sender(), amount: CLAIMABLE });
    }

    #[test]
    #[expected_failure(abort_code = EClaim, location = Self)]
    public fun test_claim() {
        use iota::test_scenario;

        let admin = @0xAD;
        let user = @0xB0B;
        
        let mut scenario = test_scenario::begin(admin);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            init(TESTI_TOKEN {}, ctx);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            claim(&mut tracker, ctx);
            assert!(table::contains(&tracker.claimed, tx_context::sender(ctx)), 2);

            test_scenario::return_shared(tracker);
        };


        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            claim(&mut tracker, ctx);

            test_scenario::return_shared(tracker);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EMint, location = Self)]
    public fun test_max_supply() {
        use iota::test_scenario;

        let admin = @0xAD;
        let user = @0xB0B;
        
        let mut scenario = test_scenario::begin(admin);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            init(TESTI_TOKEN {}, ctx);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            mint(&mut tracker, MAX_SUPPLY - INITIAL_SUPPLY, ctx);
            assert!(total_supply(&tracker) == MAX_SUPPLY, 3);

            test_scenario::return_shared(tracker);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            mint(&mut tracker, 1, ctx);

            test_scenario::return_shared(tracker);
        };

        test_scenario::end(scenario);
    }
}