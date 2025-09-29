@IsTest
private class DupSettingsTest {
    @IsTest
    static void defaults_when_no_cmdt() {
        DupSettings.clearTestOverride();
        Test.startTest();
        DupSettings s = DupSettings.load();
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assertEquals('Oldest', s.tieBreaker);
        //System.assertEquals(null, s.integrationOwnerId);
        //System.assertEquals(null, s.nextApproverUsername);
    }

    @IsTest
    static void test_override_applies() {
        DupSettings mock = new DupSettings();
        mock.integrationOwnerId = '005000000000001AAA';
        mock.tieBreaker = 'Newest';
        mock.nextApproverUsername = 'approver@example.test';
        DupSettings.setTestOverride(mock);

        Test.startTest();
        DupSettings s = DupSettings.load();
        Test.stopTest();

        System.assertEquals('Newest', s.tieBreaker);
        System.assertEquals('005000000000001AAA', s.integrationOwnerId);
        System.assertEquals('approver@example.test', s.nextApproverUsername);

        DupSettings.clearTestOverride();
    }
}
