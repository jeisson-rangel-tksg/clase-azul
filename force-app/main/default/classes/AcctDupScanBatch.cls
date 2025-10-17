public with sharing class AcctDupScanBatch implements Database.Batchable<SObject>, Database.Stateful {
    public enum ScanMode { AllPersons, CreatedToday }

    private final Integer threshold;
    private final Set<String> ruleDevNames;
    private final ScanMode mode;
    private Set<Id> visited;

    public AcctDupScanBatch(Integer threshold, Set<String> ruleDevNames, ScanMode mode) {
        if (threshold == null) {
            this.threshold = 2;
        } else {
            this.threshold = threshold;
        }
        if (ruleDevNames == null) {
            this.ruleDevNames = new Set<String>();
        } else {
            this.ruleDevNames = ruleDevNames;
        }
        if (mode == null) {
            this.mode = ScanMode.AllPersons;
        } else {
            this.mode = mode;
        }
        this.visited = new Set<Id>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (this.mode == ScanMode.CreatedToday) {
            Date today = Date.today();
            DateTime startOfDay = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));
            DateTime endOfDay = startOfDay.addDays(1);

            return Database.getQueryLocator([
                SELECT Id, PersonEmail, Name, CreatedDate
                FROM Account
                WHERE IsPersonAccount = true
                  AND CreatedDate >= :startOfDay
                  AND CreatedDate < :endOfDay
            ]);
        } else {
            return Database.getQueryLocator([
                SELECT Id, PersonEmail, Name, CreatedDate
                FROM Account
                WHERE IsPersonAccount = true
            ]);
        }
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        // 1) Skip sources already processed
        List<Account> unvisited = new List<Account>();
        for (Account a : scope) {
            if (!visited.contains(a.Id)) {
                unvisited.add(a);
            }
        }
        if (unvisited.isEmpty()) {
            return;
        }

        // 2) Pairwise dupes (Datacloud + Levenshtein)
        List<DupScanSvc.DupResult> pairs = DupScanSvc.filterDupesByEmailDistance(unvisited, this.threshold, this.ruleDevNames);
        if (pairs == null || pairs.isEmpty()) {
            return;
        }

        // 3) Decide mains per cluster
        DupSettings settings = DupSettings.load();
        List<DupClusterSvc.ClusterDecision> allDecisions = DupClusterSvc.decideMainsFromScan(pairs, settings);
        if (allDecisions == null || allDecisions.isEmpty()) {
            return;
        }

        // 4) Filter out clusters that intersect visited
        List<DupClusterSvc.ClusterDecision> decisions = new List<DupClusterSvc.ClusterDecision>();
        for (DupClusterSvc.ClusterDecision d : allDecisions) {
            Boolean intersects = false;
            for (Id x : d.all) {
                if (visited.contains(x)) {
                    intersects = true;
                    break;
                }
            }
            if (!intersects) {
                decisions.add(d);
            }
        }
        if (decisions.isEmpty()) {
            return;
        }

        // 5) Mark cluster members as visited
        for (DupClusterSvc.ClusterDecision d : decisions) {
            for (Id x : d.all) {
                visited.add(x);
            }
        }

        // 6) Stamp & submit approvals for mains; dupes get linked via Principal_Account__c
        DupConsolidationAct.stampAndSubmit(decisions);

        // 7) Debug printout (optional)
        Set<Id> printIds = collectAllIds(decisions);
        Map<Id, Account> acc = new Map<Id, Account>([
            SELECT Id, Name, PersonEmail
            FROM Account
            WHERE Id IN :printIds
        ]);
        List<DupClusterSvc.ClusterDebug> dbg = DupClusterSvc.toDebug(decisions, acc);
        for (DupClusterSvc.ClusterDebug r : dbg) {
            System.debug(LoggingLevel.INFO, 'MAIN: ' + r.main.Id + ' | ' + r.main.Name + ' | ' + r.main.PersonEmail);
            System.debug(LoggingLevel.INFO, 'DUPES: ' + r.others);
        }
    }

    public void finish(Database.BatchableContext bc) { }

    private static Set<Id> collectAllIds(List<DupClusterSvc.ClusterDecision> ds) {
        Set<Id> out = new Set<Id>();
        for (DupClusterSvc.ClusterDecision d : ds) {
            if (d != null) {
                if (d.mainId != null) {
                    out.add(d.mainId);
                }
                if (d.others != null) {
                    out.addAll(d.others);
                }
            }
        }
        return out;
    }
}
