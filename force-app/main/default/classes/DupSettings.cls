public with sharing class DupSettings {
    public String integrationOwnerId;
    public String tieBreaker;
    public String nextApproverUsername;

    private static DupSettings testOverride;

    public DupSettings() { }

    public static void setTestOverride(DupSettings s) {
        testOverride = s;
    }
    public static void clearTestOverride() {
        testOverride = null;
    }

    public static DupSettings load() {
        // In tests, honor override if provided
        if (Test.isRunningTest() && testOverride != null) {
            return testOverride;
        }

        DupSettings s = new DupSettings();
        // Safe query: handle "no rows" gracefully
        List<DupConsolidationSettings__mdt> rows = [
            SELECT IntegrationOwnerId__c, TieBreaker__c, NextApproverUsername__c
            FROM DupConsolidationSettings__mdt
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            s.integrationOwnerId = null;
            s.tieBreaker = 'Oldest';
            s.nextApproverUsername = null;
            return s;
        }

        DupConsolidationSettings__mdt cfg = rows[0];
        s.integrationOwnerId = cfg.IntegrationOwnerId__c;
        s.tieBreaker = String.isBlank(cfg.TieBreaker__c) ? 'Oldest' : String.valueOf(cfg.TieBreaker__c);
        s.nextApproverUsername = String.isBlank(cfg.NextApproverUsername__c) ? null : cfg.NextApproverUsername__c.trim();
        return s;
    }
}
