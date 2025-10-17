public with sharing class DupClusterSvc {
    public class ClusterDecision {
        public Id mainId;
        public List<Id> others;
        public List<Id> all;

        public ClusterDecision() {
            this.others = new List<Id>();
            this.all = new List<Id>();
        }
    }
    public class ClusterDebug {
        public Account main;
        public List<Account> others;

        public ClusterDebug() {
            this.others = new List<Account>();
        }
    }

    public static List<ClusterDecision> decideMainsFromScan(List<DupScanSvc.DupResult> pairs, DupSettings settings) {
        Map<Id, Set<Id>> g = new Map<Id, Set<Id>>();
        Set<Id> seed = new Set<Id>();

        for (DupScanSvc.DupResult r : pairs) {
            if (r == null) {
                continue;
            }
            if (r.source == null) {
                continue;
            }
            seed.add(r.source.Id);

            if (!g.containsKey(r.source.Id)) {
                g.put(r.source.Id, new Set<Id>());
            }
            if (r.dupes != null) {
                for (Account d : r.dupes) {
                    if (d == null) {
                        continue;
                    }
                    seed.add(d.Id);

                    if (!g.containsKey(d.Id)) {
                        g.put(d.Id, new Set<Id>());
                    }
                    g.get(r.source.Id).add(d.Id);
                    g.get(d.Id).add(r.source.Id);
                }
            }
        }

        List<Set<Id>> clusters = new List<Set<Id>>();
        Set<Id> seen = new Set<Id>();
        for (Id v : seed) {
            if (seen.contains(v)) {
                continue;
            }
            Set<Id> comp = new Set<Id>();
            List<Id> q = new List<Id>();
            q.add(v);
            seen.add(v);

            while (!q.isEmpty()) {
                Id cur = q.remove(0);
                comp.add(cur);
                Set<Id> neigh = g.get(cur);
                if (neigh == null) {
                    continue;
                }
                for (Id w : neigh) {
                    if (!seen.contains(w)) {
                        seen.add(w);
                        q.add(w);
                    }
                }
            }
            if (comp.size() > 1) {
                clusters.add(comp);
            }
        }

        if (clusters.isEmpty()) {
            return new List<ClusterDecision>();
        }

        Map<Id, Account> acc = new Map<Id, Account>([
            SELECT Id, OwnerId, CreatedDate
            FROM Account
            WHERE Id IN :flatten(clusters)
        ]);

        List<ClusterDecision> decisions = new List<ClusterDecision>();
        for (Set<Id> c : clusters) {
            ClusterDecision d = pickMain(c, acc, settings);
            if (d != null && d.mainId != null) {
                decisions.add(d);
            }
        }
        return decisions;
    }

    public static List<ClusterDebug> toDebug(List<ClusterDecision> decisions, Map<Id, Account> acc) {
        List<ClusterDebug> out = new List<ClusterDebug>();
        for (ClusterDecision d : decisions) {
            ClusterDebug dbg = new ClusterDebug();
            dbg.main = acc.get(d.mainId);
            for (Id x : d.others) {
                Account a = acc.get(x);
                if (a != null) {
                    dbg.others.add(a);
                }
            }
            out.add(dbg);
        }
        return out;
    }

    private static ClusterDecision pickMain(Set<Id> cluster, Map<Id, Account> acc, DupSettings s) {
        if (cluster == null) {
            return null;
        }
        if (cluster.isEmpty()) {
            return null;
        }

        List<Account> all = new List<Account>();
        for (Id i : cluster) {
            Account a = acc.get(i);
            if (a != null) {
                all.add(a);
            }
        }
        if (all.isEmpty()) {
            return null;
        }

        List<Account> prefer = new List<Account>();
        for (Account a : all) {
            if (String.isBlank(s.integrationOwnerId)) {
                prefer.add(a);
            } else if (a.OwnerId != s.integrationOwnerId) {
                prefer.add(a);
            }
        }

        List<Account> pool;
        if (!prefer.isEmpty()) {
            pool = prefer;
        } else {
            pool = all;
        }

        Account chosen = chooseByTieBreaker(pool, s);

        List<Account> sameTime = new List<Account>();
        for (Account a : pool) {
            if (a.CreatedDate == chosen.CreatedDate) {
                sameTime.add(a);
            }
        }
        Account stable = lowestId(sameTime);
        if (stable != null) {
            chosen = stable;
        }

        ClusterDecision res = new ClusterDecision();
        res.mainId = chosen.Id;
        for (Account a : all) {
            res.all.add(a.Id);
            if (a.Id != chosen.Id) {
                res.others.add(a.Id);
            }
        }
        return res;
    }

    private static Account chooseByTieBreaker(List<Account> pool, DupSettings s) {
        if (s.tieBreaker == 'Newest') {
            return newest(pool);
        }
        return oldest(pool);
    }
    private static Account oldest(List<Account> xs) {
        Account best = null;
        for (Account a : xs) {
            if (best == null) {
                best = a;
            } else if (a.CreatedDate < best.CreatedDate) {
                best = a;
            }
        }
        return best;
    }
    private static Account newest(List<Account> xs) {
        Account best = null;
        for (Account a : xs) {
            if (best == null) {
                best = a;
            } else if (a.CreatedDate > best.CreatedDate) {
                best = a;
            }
        }
        return best;
    }
    private static Account lowestId(List<Account> xs) {
        Account best = null;
        for (Account a : xs) {
            if (best == null) {
                best = a;
            } else if (String.valueOf(a.Id) < String.valueOf(best.Id)) {
                best = a;
            }
        }
        return best;
    }
    private static Set<Id> flatten(List<Set<Id>> clusters) {
        Set<Id> out = new Set<Id>();
        for (Set<Id> c : clusters) {
            out.addAll(c);
        }
        return out;
    }
}
