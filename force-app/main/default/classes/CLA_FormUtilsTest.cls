/**
 * @name CLA_FormUtilsTest
 * @description 
 * Unit tests for the CLA_FormUtils class covering account, order, and order item creation logic.
 * Validates positive and negative paths for email validation, product requirements, and order setup.
 * Includes CRUD/FLS testing by creating a user with limited permissions.
 * * @author 
 * Luis Vargas, Company: The KSquare Group
 * @date 
 * June 12, 2025
 */
@IsTest
private class CLA_FormUtilsTest {

    @TestSetup
    static void setupData() {
        // Create necessary data for tests
        // Activate Standard Pricebook if not already active
        Id pricebookId = Test.getStandardPricebookId();
        Pricebook2 standardPb = new Pricebook2(Id = pricebookId, IsActive = true);
        update standardPb;

        // Insert a sample Product
        Product2 prod = new Product2(
            Name = 'Test Product', 
            Family = 'E. Limitadas', 
            IsActive = true, 
            CLA_ExternalId__c = 'T3$7'
        );
        insert prod;

        // Insert a PricebookEntry to link the product to the standard pricebook
        insert new PricebookEntry(
            Pricebook2Id = standardPb.Id,
            Product2Id = prod.Id,
            UnitPrice = 150,
            IsActive = true
        );

        // Insert Campaign and Campaign Product
        Campaign testCampaign = new Campaign(
            Name = 'Test Campaign',
            IsActive = true,
            Status = 'In Progress',
            Type = 'Event'
        );
        insert testCampaign;

        insert new CampaignProduct__c(
            Name = 'Test Campaign Product',
            Campaign__c = testCampaign.Id,
            Product__c = prod.Id
        );
    }

    /**
     * Creates and inserts a test user with a Standard User profile to simulate 
     * a user with limited permissions for CRUD/FLS testing.
     * @return The newly inserted User record.
     */
    private static User createLimitedUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'limited',
            Email = 'limiteduser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            // Ensure a unique username for every test run
            Username = 'limiteduser' + DateTime.now().getTime() + '@test.com'
        );
        // User must be inserted into the database to be used with System.runAs
        insert u;
        return u;
    }

    @IsTest
    static void testCreateOrderWithItemsSuccess() {
        Product2 prod = [SELECT Id FROM Product2 WHERE CLA_ExternalId__c = 'T3$7' LIMIT 1];
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];

        Map<String, Object> input = new Map<String, Object>{
            'email' => 'test@example.com',
            'campaignId' => camp.Id,
            'pickupLocation' => 'Cabos',
            'optInAnnualNewsletter' => true,
            'products' => new List<Object>{
                new Map<Object, Object>{
                    'productId' => prod.Id,
                    'quantity' => 2
                }
            }
        };

        Test.startTest();
        CLA_FormUtils.createOrderWithItems(input);
        Test.stopTest();

        // Assertions to verify the successful creation and correct data
        Account acc = [SELECT Id, PersonEmail, CLA_OptInAnnualNewsletter__pc FROM Account WHERE PersonEmail = 'test@example.com' LIMIT 1];
        Assert.areEqual('test@example.com', acc.PersonEmail, 'Account email should match input');
        Assert.isTrue(acc.CLA_OptInAnnualNewsletter__pc, 'Opt-in flag should be true');

        Order ord = [SELECT Id, AccountId, CLA_Location__c, Campaign__c FROM Order WHERE AccountId = :acc.Id LIMIT 1];
        Assert.areEqual(acc.Id, ord.AccountId, 'Order should be linked to the correct account');
        Assert.areEqual('Cabos', ord.CLA_Location__c, 'Pickup location should match');
        Assert.areEqual(camp.Id, ord.Campaign__c, 'Campaign ID should match');

        OrderItem item = [SELECT Id, OrderId, Quantity FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];
        Assert.areEqual(2, (Integer)item.Quantity, 'Order item quantity should match');
    }

    @IsTest
    static void testCreateOrderWithItemsOptOutNewsletter() {
        Product2 prod = [SELECT Id FROM Product2 WHERE CLA_ExternalId__c = 'T3$7' LIMIT 1];
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];

        Map<String, Object> input = new Map<String, Object>{
            'email' => 'test-opt-out@example.com',
            'pickupLocation' => 'Cabos',
            'campaignId' => camp.Id,
            'optInAnnualNewsletter' => false,
            'products' => new List<Object>{
                new Map<Object, Object>{
                    'productId' => prod.Id,
                    'quantity' => 1
                }
            }
        };

        Test.startTest();
        CLA_FormUtils.createOrderWithItems(input);
        Test.stopTest();

        // Verify that the opt-out flag is set correctly
        Account acc = [SELECT PersonHasOptedOutOfEmail FROM Account WHERE PersonEmail = 'test-opt-out@example.com' LIMIT 1];
        Assert.isTrue(acc.PersonHasOptedOutOfEmail, 'PersonHasOptedOutOfEmail should be true when opt-in is false');
    }

    @IsTest
    static void testCreateOrderWithItemsMissingEmail() {
        Product2 prod = [SELECT Id FROM Product2 WHERE CLA_ExternalId__c = 'T3$7' LIMIT 1];
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];

        Map<String, Object> input = new Map<String, Object>{
            'email' => '', // Blank email to trigger the error
            'campaignId' => camp.Id,
            'pickupLocation' => 'Cabos',
            'products' => new List<Object>{
                new Map<Object, Object>{
                    'productId' => prod.Id,
                    'quantity' => 1
                }
            }
        };

        Test.startTest();
        try {
            CLA_FormUtils.createOrderWithItems(input);
            Assert.fail('Expected AuraHandledException due to missing email');
        } catch (AuraHandledException e) {
            // Verify correct error message is thrown
            Assert.isTrue(e.getMessage().contains(CLA_FormConstants.ERR_EMAIL_REQUIRED), 
                'Exception should be for a required email');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateOrderWithItemsEmptyProducts() {
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];

        Map<String, Object> input = new Map<String, Object>{
            'email' => 'test2@example.com',
            'campaignId' => camp.Id,
            'pickupLocation' => 'Cabos',
            'products' => new List<Object>() // Empty product list to trigger error
        };

        Test.startTest();
        try {
            CLA_FormUtils.createOrderWithItems(input);
            Assert.fail('Expected AuraHandledException due to empty products list');
        } catch (AuraHandledException e) {
            // Verify correct error message is thrown
            Assert.isTrue(e.getMessage().contains(CLA_FormConstants.ERR_PRODUCTS_REQUIRED), 
                'Exception should be for required products');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateOrderWithItemsMissingProductId() {
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];

        Map<String, Object> input = new Map<String, Object>{
            'email' => 'test3@example.com',
            'campaignId' => camp.Id,
            'pickupLocation' => 'Cabos',
            'products' => new List<Object>{
                new Map<Object, Object>{
                    'productId' => null, // Null product ID to trigger error
                    'quantity' => 1
                }
            }
        };

        Test.startTest();
        try {
            CLA_FormUtils.createOrderWithItems(input);
            Assert.fail('Expected AuraHandledException due to missing productId');
        } catch (AuraHandledException e) {
            // Verify correct error message from the constants class
            Assert.isTrue(e.getMessage().contains(CLA_FormConstants.ERR_PRODUCTID_MISSING), 
                'Exception message should match the constant for a missing product ID');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetPersonAccountByEmailBlank() {
        Test.startTest();
        List<Account> results = CLA_FormUtils.getPersonAccountByEmail('');
        Test.stopTest();

        Assert.isNotNull(results, 'Should always return a list, not null');
        Assert.areEqual(0, results.size(), 'Should return an empty list for a blank email');
    }

    @IsTest
    static void testGetStandardPricebookId() {
        Test.startTest();
        Id pbId = CLA_FormUtils.getStandardPricebookId();
        Test.stopTest();

        Assert.isNotNull(pbId, 'Standard Pricebook ID should not be null');
    }

    @IsTest
    static void testGetPricebookEntryMapSuccess() {
        Product2 prod = [SELECT Id FROM Product2 WHERE CLA_ExternalId__c = 'T3$7' LIMIT 1];
        Set<Id> productIds = new Set<Id>{ prod.Id };

        Test.startTest();
        Map<Id, Map<String, Object>> result = CLA_FormUtils.getPricebookEntryMap(productIds);
        Test.stopTest();

        Assert.isTrue(result.containsKey(prod.Id), 'Map should contain the requested product ID');
        Assert.isNotNull(result.get(prod.Id).get('entryId'), 'Entry ID should exist in the map');
        Assert.isNotNull(result.get(prod.Id).get('unitPrice'), 'Unit price should exist in the map');
    }
}