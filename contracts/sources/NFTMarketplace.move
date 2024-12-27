address 0x75cfca25296896f907a457e20a245f9af304cb1e48723d864e17f2e08ad93159 {

    module NFTMarketplace {
        use 0x1::signer;
        use 0x1::vector;
        use 0x1::coin;
        use 0x1::aptos_coin;
        use 0x1::timestamp;

        struct NFT has store, key {
            id: u64,
            owner: address,
            name: vector<u8>,
            description: vector<u8>,
            uri: vector<u8>,
            price: u64,
            for_sale: bool,
            rarity: u8
        }

        struct Marketplace has key {
            nfts: vector<NFT>,
        }

        struct MarketplaceV2 has key {
            nfts: vector<NFT>,
            auctions: vector<Auction>,
        }

        struct ListedNFT has copy, drop {
            id: u64,
            price: u64,
            rarity: u8
        }

        struct Auction has store, copy, drop {
            nft_id: u64,
            seller: address,
            start_price: u64,
            current_bid: u64,
            highest_bidder: address,
            end_time: u64,
        }

        const MARKETPLACE_FEE_PERCENT: u64 = 2;

        public entry fun initialize(account: &signer) acquires Marketplace {
            if (!exists<MarketplaceV2>(signer::address_of(account))) {
                if (exists<Marketplace>(signer::address_of(account))) {
                    // Migrate from V1 to V2
                    let Marketplace { nfts } = move_from<Marketplace>(signer::address_of(account));
                    let marketplace_v2 = MarketplaceV2 {
                        nfts,
                        auctions: vector::empty<Auction>(),
                    };
                    move_to(account, marketplace_v2);
                } else {
                    // Initialize new V2 marketplace
                    let marketplace_v2 = MarketplaceV2 {
                        nfts: vector::empty<NFT>(),
                        auctions: vector::empty<Auction>(),
                    };
                    move_to(account, marketplace_v2);
                }
            }
        }

        #[view]
        public fun is_marketplace_initialized(marketplace_addr: address): bool {
            exists<Marketplace>(marketplace_addr) || exists<MarketplaceV2>(marketplace_addr)
        }

        public entry fun mint_nft(account: &signer, name: vector<u8>, description: vector<u8>, uri: vector<u8>, rarity: u8) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(signer::address_of(account));
            let nft_id = vector::length(&marketplace.nfts);

            let new_nft = NFT {
                id: nft_id,
                owner: signer::address_of(account),
                name,
                description,
                uri,
                price: 0,
                for_sale: false,
                rarity
            };

            vector::push_back(&mut marketplace.nfts, new_nft);
        }

        #[view]
        public fun get_nft_details(marketplace_addr: address, nft_id: u64): (u64, address, vector<u8>, vector<u8>, vector<u8>, u64, bool, u8) acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);

            (nft.id, nft.owner, nft.name, nft.description, nft.uri, nft.price, nft.for_sale, nft.rarity)
        }

        public entry fun list_for_sale(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 100);
            assert!(!nft_ref.for_sale, 101);
            assert!(price > 0, 102);

            nft_ref.for_sale = true;
            nft_ref.price = price;
        }

        public entry fun set_price(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 200);
            assert!(price > 0, 201);

            nft_ref.price = price;
        }

        public entry fun purchase_nft(account: &signer, marketplace_addr: address, nft_id: u64, payment: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.for_sale, 400);
            assert!(payment >= nft_ref.price, 401);

            let fee = (nft_ref.price * MARKETPLACE_FEE_PERCENT) / 100;
            let seller_revenue = payment - fee;

            coin::transfer<aptos_coin::AptosCoin>(account, marketplace_addr, seller_revenue);
            coin::transfer<aptos_coin::AptosCoin>(account, signer::address_of(account), fee);

            nft_ref.owner = signer::address_of(account);
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }

        #[view]
        public fun is_nft_for_sale(marketplace_addr: address, nft_id: u64): bool acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.for_sale
        }

        #[view]
        public fun get_nft_price(marketplace_addr: address, nft_id: u64): u64 acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.price
        }

        public entry fun transfer_ownership(account: &signer, marketplace_addr: address, nft_id: u64, new_owner: address) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 300);
            assert!(nft_ref.owner != new_owner, 301);

            nft_ref.owner = new_owner;
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }

        #[view]
        public fun get_owner(marketplace_addr: address, nft_id: u64): address acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.owner
        }

        #[view]
        public fun get_all_nfts_for_owner(marketplace_addr: address, owner_addr: address, limit: u64, offset: u64): vector<u64> acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.owner == owner_addr) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }

        #[view]
        public fun get_all_nfts_for_sale(marketplace_addr: address, limit: u64, offset: u64): vector<ListedNFT> acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nfts_for_sale = vector::empty<ListedNFT>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.for_sale) {
                    let listed_nft = ListedNFT { id: nft.id, price: nft.price, rarity: nft.rarity };
                    vector::push_back(&mut nfts_for_sale, listed_nft);
                };
                mut_i = mut_i + 1;
            };

            nfts_for_sale
        }

        public fun min(a: u64, b: u64): u64 {
            if (a < b) { a } else { b }
        }

        #[view]
        public fun get_nfts_by_rarity(marketplace_addr: address, rarity: u8): vector<u64> acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let mut_i = 0;
            while (mut_i < nfts_len) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.rarity == rarity) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }

        public entry fun create_auction(account: &signer, marketplace_addr: address, nft_id: u64, start_price: u64, duration: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 500); // Caller is not the owner
            assert!(!nft_ref.for_sale, 501); // NFT is already listed for sale

            let auction = Auction {
                nft_id,
                seller: signer::address_of(account),
                start_price,
                current_bid: start_price,
                highest_bidder: signer::address_of(account),
                end_time: timestamp::now_seconds() + duration,
            };

            vector::push_back(&mut marketplace.auctions, auction);
            nft_ref.for_sale = true;
        }

        public entry fun place_bid(account: &signer, marketplace_addr: address, auction_id: u64, bid_amount: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let auction_ref = vector::borrow_mut(&mut marketplace.auctions, auction_id);

            assert!(bid_amount > auction_ref.current_bid, 600); // Bid is too low
            assert!(timestamp::now_seconds() < auction_ref.end_time, 601); // Auction has ended

            // Return the previous bid to the previous highest bidder
            if (auction_ref.highest_bidder != auction_ref.seller) {
                coin::transfer<aptos_coin::AptosCoin>(account, auction_ref.highest_bidder, auction_ref.current_bid);
            };

            // Update auction state
            auction_ref.current_bid = bid_amount;
            auction_ref.highest_bidder = signer::address_of(account);

            // Transfer the new bid amount from the bidder to the marketplace
            coin::transfer<aptos_coin::AptosCoin>(account, marketplace_addr, bid_amount);
        }

        public entry fun end_auction(account: &signer, marketplace_addr: address, auction_id: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            let auction = vector::remove(&mut marketplace.auctions, auction_id);

            assert!(timestamp::now_seconds() >= auction.end_time, 700); // Auction has not ended yet

            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, auction.nft_id);

            if (auction.highest_bidder != auction.seller) {
                // Transfer ownership of the NFT
                nft_ref.owner = auction.highest_bidder;
                
                // Transfer the winning bid to the seller
                coin::transfer<aptos_coin::AptosCoin>(account, auction.seller, auction.current_bid);
            };

            // Reset NFT sale status
            nft_ref.for_sale = false;
        }

        #[view]
        public fun get_all_auctions(marketplace_addr: address): vector<Auction> acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            marketplace.auctions
        }

        public entry fun fuse_nfts(account: &signer, marketplace_addr: address, nft_id1: u64, nft_id2: u64) acquires MarketplaceV2 {
            let marketplace = borrow_global_mut<MarketplaceV2>(marketplace_addr);
            
            // Check ownership and availability of both NFTs
            assert!(vector::borrow(&marketplace.nfts, nft_id1).owner == signer::address_of(account), 800);
            assert!(vector::borrow(&marketplace.nfts, nft_id2).owner == signer::address_of(account), 801);
            assert!(!vector::borrow(&marketplace.nfts, nft_id1).for_sale, 802);
            assert!(!vector::borrow(&marketplace.nfts, nft_id2).for_sale, 803);

            // Remove the two NFTs (in reverse order to keep indices valid)
            let nft2 = vector::remove(&mut marketplace.nfts, nft_id2);
            let nft1 = vector::remove(&mut marketplace.nfts, nft_id1);

            // Create a new fused NFT
            let new_rarity = (nft1.rarity + nft2.rarity) / 2 + 1; // Simple fusion logic
            if (new_rarity > 4) { new_rarity = 4; }; // Cap rarity at 4

            let fused_nft = NFT {
                id: vector::length(&marketplace.nfts),
                owner: signer::address_of(account),
                name: b"Fused NFT",
                description: b"This NFT is a result of fusion",
                uri: nft1.uri, // Use the URI of the first NFT for simplicity
                price: 0,
                for_sale: false,
                rarity: new_rarity,
            };

            vector::push_back(&mut marketplace.nfts, fused_nft);

            // Explicitly drop the unused NFTs
            let NFT { id: _, owner: _, name: _, description: _, uri: _, price: _, for_sale: _, rarity: _ } = nft1;
            let NFT { id: _, owner: _, name: _, description: _, uri: _, price: _, for_sale: _, rarity: _ } = nft2;
        }

        #[view]
        public fun get_last_minted_nft(marketplace_addr: address, user_addr: address): (u64, vector<u8>, vector<u8>, vector<u8>, u8) acquires MarketplaceV2 {
            let marketplace = borrow_global<MarketplaceV2>(marketplace_addr);
            let nfts_len = vector::length(&marketplace.nfts);
            let mut_i = nfts_len;

            while (mut_i > 0) {
                mut_i = mut_i - 1;
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.owner == user_addr) {
                    return (nft.id, nft.name, nft.description, nft.uri, nft.rarity)
                };
            };

            abort 900 // No NFT found for the user
        }
    }
}

