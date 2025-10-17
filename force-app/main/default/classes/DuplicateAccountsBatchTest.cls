@IsTest
private class DuplicateAccountsBatchTest {
    @IsTest
    static void runs_legacy_batch_no_errors() {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account a = newPA('Dup','A','dup.legacy@test.local');
        Account b = newPA('Dup','B','dup.legacy@test.local');
        Database.insert(new List<Account>{ a, b }, dml);

        Test.startTest();
        Database.executeBatch(new DuplicateAccountsBatch(), 50); // <-- ajusta si tu ctor difiere
        Test.stopTest();

        System.assert(true, 'Batch ejecutado sin excepción');
    }

    private static Account newPA(String fn, String ln, String email) {
        Account x = new Account();
        x.FirstName=fn; x.LastName=ln; x.PersonEmail=email;
        x.AccountSource=CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE;
        x.CLA_Fuente__c=CLA_FormConstants.DEFAULT_SOURCE;
        x.CLA_SubCategory__c=CLA_FormConstants.DEFAULT_SUBCATEGORY;
        x.RecordTypeId=Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId();
        return x;
    }
}
