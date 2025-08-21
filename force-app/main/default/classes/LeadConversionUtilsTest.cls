@IsTest
private class LeadConversionUtilsTest {

    @IsTest
    static void test_updateAccountInfoFromLead_setsMappedFields() {

        List<RecordType> rec = [SELECT Id From RecordType Where DeveloperName = 'PersonAccount'];
        // Minimal lead with several fields used by the mapper
        Lead l = new Lead(
            LastName = 'Utils',
            Email = 'utils.mapper@test.com',
            City = 'testCity',
            LeadSource = 'ECOMMERCE',
            Category__c = 'E-COMMERCE',
            Sub_Category__c = 'Test',
            State = 'testState',
            Country = 'testCountry',
            PostalCode = '050001',
            Street = 'testStreet',
            Title = 'test',
            MobilePhone = '123123'
        );
        insert l;

        // Stub target account id (would be the result of a conversion)
        Account a = new Account(
            FirstName = 'Test',
            LastName = 'Temp',
            PersonEmail = 'utils.mapper@test.com', 
            AccountSource = 'ECOMMERCE', 
            CLA_Fuente__c = 'E-COMMERCE', 
            CLA_SubCategory__c = 'test', 
            CLA_OptIn__pc = true,
            RecordTypeId = rec.get(0).Id);
        insert a;

        Account mapped = LeadConversionUtils.updateAccountInfoFromLead(l.Id, a.Id);

        // Validate key fields were copied (no DML here; method only returns the Account to update)
        System.assertEquals(a.Id, mapped.Id, 'Should keep same Account Id');
        System.assertEquals('testCity', mapped.PersonMailingCity);
        System.assertEquals('testState', mapped.PersonMailingState);
        System.assertEquals('testCountry', mapped.PersonMailingCountry);
        System.assertEquals('050001', mapped.PersonMailingPostalCode);
        System.assertEquals('testStreet', mapped.PersonMailingStreet);
        System.assertEquals('test', mapped.PersonTitle);
        System.assertEquals('123123', mapped.PersonMobilePhone);
        System.assertEquals('utils.mapper@test.com', mapped.PersonEmail);
    }
}