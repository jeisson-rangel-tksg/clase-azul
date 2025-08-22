/**
 * @description 
 * Unit tests for the CLA_FormVPMPController class. This class tests the retrieval of 
 * campaign products, finding person accounts by email, and the invocation of the 
 * order creation process.
 *
 * @author 
 * Luis Vargas, Company: The KSquare Group
 * @date 
 * June 12, 2025
 */
@IsTest
private class CLA_FormVPMPControllerTest {

    @TestSetup
    static void setupData() {
        Campaign camp = new Campaign(Name = 'Test Campaign', IsActive = true);
        insert camp;

        Product2 prod = new Product2(
            Name = 'Test Campaign Product', 
            Family = 'E. Limitadas', 
            IsActive = true,
            CLA_ExternalId__c = 'T3ST'
        );
        insert prod;

        CampaignProduct__c campaignProductLink = new CampaignProduct__c(
            Campaign__c = camp.Id,
            Product__c = prod.Id
        );
        insert campaignProductLink;

        Account pa = new Account(
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'john.doe@test.com',
            CLA_OptInAnnualNewsletter__pc = true,
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId()
        );
        insert pa;
        
        Id pricebookId = Test.getStandardPricebookId();
        Pricebook2 standardPb = new Pricebook2(Id = pricebookId, IsActive = true);
        update standardPb;

        insert new PricebookEntry(
            Pricebook2Id = standardPb.Id,
            Product2Id = prod.Id,
            UnitPrice = 200,
            IsActive = true
        );

        Campaign testCampaign = new Campaign(
            Name = 'Test Campaign',
            IsActive = true,
            Status = 'In Progress',
            Type = 'Event'
        );
        insert testCampaign;
    }

    @IsTest
    static void testGetCampaignProductsSuccess() {
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];
        
        Test.startTest();
        List<Product2> products = CLA_FormVPMPController.getCampaignProducts(camp.Id);
        Test.stopTest();

        Assert.areEqual(1, products.size(), 'Should return one product for the campaign.');
        Assert.areEqual('Test Campaign Product', products[0].Name, 'The correct product should be returned.');
    }

    @IsTest
    static void testGetCampaignProductsNoProducts() {
        Campaign campWithoutProducts = new Campaign(Name = 'Empty Campaign', IsActive = true);
        insert campWithoutProducts;

        Test.startTest();
        List<Product2> products = CLA_FormVPMPController.getCampaignProducts(campWithoutProducts.Id);
        Test.stopTest();

        Assert.isNotNull(products, 'Should return an empty list, not null.');
        Assert.areEqual(0, products.size(), 'Should return zero products for an empty campaign.');
    }

    @IsTest
    static void testGetPersonAccountByEmailFound() {
        Test.startTest();
        Map<String, Object> result = CLA_FormVPMPController.getPersonAccountByEmail('john.doe@test.com');
        Test.stopTest();

        Account pa = [SELECT Id, CLA_OptInAnnualNewsletter__pc FROM Account WHERE PersonEmail = 'john.doe@test.com' LIMIT 1];

        Assert.isNotNull(result, 'Result map should not be null.');
        Assert.areEqual(pa.Id, (Id)result.get('accountId'), 'Should return the correct account ID.');
        Assert.areEqual(true, (Boolean)result.get('optInAnnualNewsletter'), 'Should return the correct opt-in status.');
    }

    @IsTest
    static void testGetPersonAccountByEmailNotFound() {
        Test.startTest();
        Map<String, Object> result = CLA_FormVPMPController.getPersonAccountByEmail('jane.doe@test.com');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result map should not be null.');
        Assert.isNull(result.get('accountId'), 'Account ID should be null for a non-existent email.');
        Assert.areEqual(false, (Boolean)result.get('optInAnnualNewsletter'), 'Opt-in should be false for a non-existent email.');
    }

    @IsTest
    static void testGetPersonAccountByEmailInvalid() {
        Test.startTest();
        try {
            CLA_FormVPMPController.getPersonAccountByEmail('');
            Assert.fail('Expected AuraHandledException for blank email.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Script-thrown'), 'Exception message expected.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateOrdersSuccess() {
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Test Campaign Product' LIMIT 1];
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Test Campaign' LIMIT 1];
        
        Map<String, Object> input = new Map<String, Object>{
            'email' => 'new.customer@test.com',
            'firstName' => 'New',
            'lastName' => 'Customer',
            'campaignId' => camp.Id,
            'products' => new List<Object>{
                new Map<Object, Object>{
                    'productId' => prod.Id,
                    'quantity' => 3.0
                }
            }
        };

        Test.startTest();
        CLA_FormVPMPController.createOrders(input);
        Test.stopTest();

        Account newAcc = [SELECT Id FROM Account WHERE PersonEmail = 'new.customer@test.com'];
        Assert.isNotNull(newAcc, 'A new person account should have been created.');

        Order newOrd = [SELECT Id FROM Order WHERE AccountId = :newAcc.Id];
        Assert.isNotNull(newOrd, 'A new order should have been created.');

        List<OrderItem> items = [SELECT Id FROM OrderItem WHERE OrderId = :newOrd.Id];
        Assert.areEqual(1, items.size(), 'An order item should have been created.');
    }
}