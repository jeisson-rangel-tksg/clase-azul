@IsTest
private class LeadConversionControllerTest {

    @TestSetup
    static void setupLeads() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            Alias = 'tuser',
            Email = 'test@example.com',
            LastName = 'Tester',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Bogota',
            IsActive = true,
            UserName = 'testuser' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
    }

    @IsTest
    static void testMissingEmailParam() {
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/convertLeadByEmail';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        LeadConversionController.LeadConversionResponse res = LeadConversionController.convertLeadByEmail();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('Missing required query parameter: email', res.message);
    }

    @IsTest
    static void testLeadNotFound() {
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/convertLeadByEmail';
        req.addParameter('email', 'notfound@example.com');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        LeadConversionController.LeadConversionResponse res = LeadConversionController.convertLeadByEmail();
        System.assertEquals(404, RestContext.response.statusCode);
        System.assert(res.message.contains('No leads found'));
    }

    @IsTest
    static void testAlreadyConvertedLead() {
        Lead lead = new Lead(
            FirstName = 'Lead2',
            LastName = 'Converted2',
            Email = 'converted2@example.com',
            Status = 'Qualified',
            LeadSource = 'COLLECTOR',
            Category__c = 'DIGITAL CELLAR',
            Sub_Category__c = 'Test',
            OwnerId = UserInfo.getUserId()
        );
        insert lead;

        lead.Account_Owner_Id__c = UserInfo.getUserId();
        update lead;

        // Convert manually
        Test.startTest();
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setConvertedStatus(LeadConversionController.getDefaultConvertedStatus());
        lc.setDoNotCreateOpportunity(true);
        Database.convertLead(lc);
        Test.stopTest();

        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/convertLeadByEmail';
        req.addParameter('email', 'converted2@example.com');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        LeadConversionController.LeadConversionResponse res = LeadConversionController.convertLeadByEmail();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(res.message.contains('already converted'));
    }

    @IsTest
    static void testLeadConvertedSuccessfully() {
        Id testUserId = [SELECT Id FROM User WHERE Alias = 'tuser' LIMIT 1].Id;

        Lead lead = new Lead(
            FirstName = 'Lead',
            LastName = 'ConvertMe',
            Email = 'success@example.com',
            Status = 'Qualified',
            LeadSource = 'COLLECTOR',
            Category__c = 'DIGITAL CELLAR',
            Sub_Category__c = 'Test',
            Account_Owner_Id__c = testUserId,
            OwnerId = UserInfo.getUserId()
        );
        insert lead;

        lead.Account_Owner_Id__c = UserInfo.getUserId();
        update lead;

        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/convertLeadByEmail';
        req.addParameter('email', 'success@example.com');
        req.addParameter('isOpportunity', 'true');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        LeadConversionController.LeadConversionResponse res = LeadConversionController.convertLeadByEmail();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Lead converted successfully.', res.message);
        System.assertNotEquals(null, res.accountId);
    }
}