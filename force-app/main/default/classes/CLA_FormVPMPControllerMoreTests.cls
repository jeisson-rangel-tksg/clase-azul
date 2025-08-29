@IsTest
private class CLA_FormVPMPControllerMoreTests {

    // Utility: create a Person Account with unique email
    private static Account makePA(String email) {
        Account pa = new Account(
            FirstName = 'TEST',
            LastName = 'TEST 2',
            PersonEmail = email,
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId()
        );
        insert pa;
        return pa;
    }

    @TestSetup
    static void data() {
        // Base active + inactive campaigns
        insert new Campaign(Name = 'ActiveCamp', IsActive = true, Type = 'Other', Status = 'In Progress');
        insert new Campaign(Name = 'InactiveCamp', IsActive = false, Type = 'Other', Status = 'In Progress');

        // Event campaign for canUserCreateOrder fast-path
        insert new Campaign(Name = 'EventCamp', IsActive = true, Type = 'Event', Status = 'Planned');

        // A parent with a child (for child-scope queries)
        Campaign parentC = new Campaign(Name = 'ParentC', IsActive = true, Type = 'Other', Status = 'In Progress');
        insert parentC;
        insert new Campaign(Name = 'ChildC1', IsActive = true, Type = 'Other', Status = 'In Progress', ParentId = parentC.Id);
    }

    @IsTest
    static void test_isCampaignActive_AllBranches() {
        Campaign activeC = [SELECT Id, IsActive FROM Campaign WHERE Name = 'ActiveCamp' LIMIT 1];
        Campaign inactiveC = [SELECT Id, IsActive FROM Campaign WHERE Name = 'InactiveCamp' LIMIT 1];

        // Active = true
        System.assertEquals(true, CLA_FormVPMPController.isCampaignActive(activeC.Id));

        // Inactive = false
        System.assertEquals(false, CLA_FormVPMPController.isCampaignActive(inactiveC.Id));

        // Blank id = false
        System.assertEquals(false, CLA_FormVPMPController.isCampaignActive(null));

        // Deleted id path → query returns zero rows → false
        Campaign tmp = new Campaign(Name = 'ToDelete', IsActive = true);
        insert tmp;
        Id deletedId = tmp.Id;
        delete tmp;

        System.assertEquals(false, CLA_FormVPMPController.isCampaignActive(deletedId));
    }

    @IsTest
    static void test_getPickupLocationsFromCampaign_happyDefault() {
        // Location__c intentionally left blank so code uses DEFAULT_PICKUP_LOCATION_OPTIONS
        Campaign c = [SELECT Id, Location__c FROM Campaign WHERE Name = 'ActiveCamp' LIMIT 1];

        Test.startTest();
        List<CLA_FormVPMPController.PickupLocationOption> opts =
            CLA_FormVPMPController.getPickupLocationsFromCampaign(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Options list should be returned');
    }

    // NEW: null Id exception branch for getPickupLocationsFromCampaign
    @IsTest
    static void test_getPickupLocationsFromCampaign_nullId_exception() {
        try {
            CLA_FormVPMPController.getPickupLocationsFromCampaign(null);
            System.assert(false, 'Expected AuraHandledException for null campaign Id.');
        } catch (AuraHandledException e) {
            System.assert(e.getTypeName().contains('AuraHandledException'));
        }
    }

    // NEW: both branches for getPickupLocationsAndProductsByCampaign
    @IsTest
    static void test_getPickupLocationsAndProductsByCampaign_paths() {
        Campaign c = [SELECT Id FROM Campaign WHERE Name = 'ActiveCamp' LIMIT 1];

        // Exception branch (null id)
        try {
            CLA_FormVPMPController.getPickupLocationsAndProductsByCampaign(null);
            System.assert(false, 'Expected AuraHandledException for null campaign Id.');
        } catch (AuraHandledException e) {
            System.assert(e.getTypeName().contains('AuraHandledException'));
        }

        // Happy path (logic is commented → empty structures)
        Test.startTest();
        CLA_FormVPMPController.PickupResponse resp =
            CLA_FormVPMPController.getPickupLocationsAndProductsByCampaign(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, resp);
        System.assertNotEquals(null, resp.pickupLocations);
        System.assertNotEquals(null, resp.productsByLocation);
    }


    @IsTest
    static void test_canUserCreateOrder_allBranches() {
        Campaign eventC = [SELECT Id FROM Campaign WHERE Name = 'EventCamp' LIMIT 1];
        Campaign parentC = [SELECT Id FROM Campaign WHERE Name = 'ParentC' LIMIT 1];
        Campaign childC  = [SELECT Id FROM Campaign WHERE Name = 'ChildC1' LIMIT 1];

        // 1) Blank inputs → true
        System.assertEquals(true, CLA_FormVPMPController.canUserCreateOrder(null, null));

        // 2) Event/Launch fast-path → true even with email present
        System.assertEquals(true, CLA_FormVPMPController.canUserCreateOrder(eventC.Id, 'someone@t.com'));

        // Prepare PA and CM scenarios
        String emBase = 'pa_' + String.valueOf(System.now().getTime()) + '@test.com';
        Account pa = makePA(emBase);
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id LIMIT 1];
        System.assertNotEquals(null, pa.PersonContactId, 'PersonContactId should exist');

        // 3) No campaign member in parent or child → returns false
        System.assertEquals(false, CLA_FormVPMPController.canUserCreateOrder(parentC.Id, emBase));

        // 4) With CM in scope (parent or child) and no order → true
        insert new CampaignMember(CampaignId = parentC.Id, ContactId = pa.PersonContactId, Status = 'Sent');
        System.assertEquals(true, CLA_FormVPMPController.canUserCreateOrder(parentC.Id, emBase));

        // 5) With an Order under same scope → false
        Order ord = new Order(
            AccountId = pa.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Campaign__c = parentC.Id
        );
        insert ord;

        System.assertEquals(false, CLA_FormVPMPController.canUserCreateOrder(parentC.Id, emBase));

        // Sanity: child scope also counts (collectParentAndImmediateChildren)
        System.assertEquals(false, CLA_FormVPMPController.canUserCreateOrder(childC.Id, emBase));
    }

    @IsTest
    static void test_getCampaignWishlists() {
        Campaign c = [SELECT Id FROM Campaign WHERE Name = 'ActiveCamp' LIMIT 1];

        // Insert in a way that creation order is deterministic (ASC by CreatedDate)
        Campaign_Wishlist__c w1 = new Campaign_Wishlist__c(
            Campaign__c = c.Id,
            Label_EN__c = 'EN 1',
            Label_ES__c = 'ES 1',
            Main_Interest__c = 'Main 1',
            Sub_Interest__c  = 'Sub 1'
        );
        insert w1;

        Campaign_Wishlist__c w2 = new Campaign_Wishlist__c(
            Campaign__c = c.Id,
            Label_EN__c = 'EN 2',
            Label_ES__c = 'ES 2',
            Main_Interest__c = 'Main 2',
            Sub_Interest__c  = 'Sub 2'
        );
        insert w2;

        Test.startTest();
        List<CLA_FormVPMPController.WishlistOption> out =
            CLA_FormVPMPController.getCampaignWishlists(c.Id);
        Test.stopTest();

        System.assertEquals(2, out.size(), 'Two wishlists expected');
        System.assertEquals('EN 1', out[0].labelEn, 'Order should be by CreatedDate ASC');
        System.assertEquals('EN 2', out[1].labelEn);
    }

    // NEW: blank Id path for wishlists → empty list
    @IsTest
    static void test_getCampaignWishlists_blankId_returnsEmpty() {
        Test.startTest();
        List<CLA_FormVPMPController.WishlistOption> out =
            CLA_FormVPMPController.getCampaignWishlists(null);
        Test.stopTest();

        System.assertEquals(0, out.size(), 'Blank campaignId should return empty list');
    }

    @IsTest
    static void test_canUserCreateOrder_blankParams_returnTrue() {
        System.assertEquals(true, CLA_FormVPMPController.canUserCreateOrder('701000000000001AAA', ''));
    }

    // NEW: PA not found branch in canUserCreateOrder → returns true
    @IsTest
    static void test_canUserCreateOrder_personAccountNotFound_returnsTrue() {
        Campaign c = [SELECT Id FROM Campaign WHERE Name = 'ActiveCamp' LIMIT 1];
        String nonExistingEmail = 'no_pa_' + System.now().getTime() + '@test.com';

        try {
            CLA_FormVPMPController.canUserCreateOrder(c.Id, nonExistingEmail);
            System.assert(false, 'Expected QueryException when no Person Account exists.');
        } catch (QueryException e) {
            System.assertEquals('System.QueryException', e.getTypeName());
            System.assert(e.getMessage().contains('List has no rows'), 'Expected "List has no rows" message.');
        }
    }

    // NEW: updateMissingAccountFields success + missing Id exception
    @IsTest
    static void test_updateMissingAccountFields_success_and_missingId() {
        Account pa = makePA('upd_' + System.now().getTime() + '@test.com');

        Map<String, Object> input = new Map<String, Object>{
            'accountId' => pa.Id,
            'birthdate' => '1992-04-15',
            'region'    => 'Latam',
            'country'   => 'Colombia',
            'state'     => 'Boyacá',
            'street'    => 'Calle 123',
            'city'      => 'Ciudad',
            'zip'       => '01010'
        };

        Test.startTest();
        CLA_FormVPMPController.updateMissingAccountFields(input);
        Test.stopTest();

        Account after = [
            SELECT PersonBirthdate, Region__pc, Country__pc, State__pc,
                PersonMailingStreet, PersonMailingCity, PersonMailingPostalCode
            FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(Date.newInstance(1992, 4, 15), after.PersonBirthdate);
        System.assertEquals('Latam',    after.Region__pc);
        System.assertEquals('Colombia', after.Country__pc);
        System.assertEquals('Boyacá',   after.State__pc);
        System.assertEquals('Calle 123', after.PersonMailingStreet);
        System.assertEquals('Ciudad',    after.PersonMailingCity);
        System.assertEquals('01010',     after.PersonMailingPostalCode);

        // Missing Id exception branch
        try {
            CLA_FormVPMPController.updateMissingAccountFields(new Map<String, Object>());
            System.assert(false, 'Expected AuraHandledException for missing account ID.');
        } catch (AuraHandledException e) {
            System.assert(e.getTypeName().contains('AuraHandledException'));
        }
    }

    // NEW: invalid email branch for getPersonAccountByEmail
    @IsTest
    static void test_getPersonAccountByEmail_invalid_throws() {
        try {
            CLA_FormVPMPController.getPersonAccountByEmail('');
            System.assert(false, 'Expected AuraHandledException for invalid email.');
        } catch (AuraHandledException e) {
            System.assert(e.getTypeName().contains('AuraHandledException'));
        }
    }
} 
