public with sharing class RunDupScanBatchFlowAction {
    public class Request {
        @InvocableVariable
        public Integer threshold; // optional; default 2

        @InvocableVariable
        public List<String> ruleDeveloperNames; // optional; Duplicate Rule developer names

        @InvocableVariable
        public Integer batchSize; // optional; default 200
    }

    public class Result {
        @InvocableVariable public String jobId;
        @InvocableVariable public Integer threshold;
        @InvocableVariable public Integer batchSize;
        @InvocableVariable public String mode; // "CreatedToday"
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Run Duplicate Scan Batch (Created Today)'
        description='Executes AcctDupScanBatch in CreatedToday mode for Person Accounts created today.'
    )
    public static List<Result> run(List<Request> inputs) {
        List<Result> out = new List<Result>();

        if (inputs == null || inputs.isEmpty()) {
            inputs = new List<Request>();
            inputs.add(new Request());
        }

        for (Request r : inputs) {
            Result res = new Result();
            res.success = false;
            res.mode = String.valueOf(AcctDupScanBatch.ScanMode.CreatedToday);

            Integer thresholdLocal;
            if (r != null && r.threshold != null) {
                thresholdLocal = r.threshold;
            } else {
                thresholdLocal = 2;
            }

            Integer batchSizeLocal;
            if (r != null && r.batchSize != null) {
                batchSizeLocal = r.batchSize;
            } else {
                batchSizeLocal = 200;
            }

            Set<String> ruleNames = new Set<String>();
            if (r != null && r.ruleDeveloperNames != null) {
                for (String name : r.ruleDeveloperNames) {
                    if (String.isBlank(name)) {
                        continue;
                    }
                    ruleNames.add(name.trim());
                }
            }

            AcctDupScanBatch.ScanMode mode = AcctDupScanBatch.ScanMode.CreatedToday;
            AcctDupScanBatch b = new AcctDupScanBatch(thresholdLocal, ruleNames, mode);

            try {
                String jobId = Database.executeBatch(b, batchSizeLocal);
                res.jobId = jobId;
                res.threshold = thresholdLocal;
                res.batchSize = batchSizeLocal;
                res.success = true;
                res.message = 'Batch enqueued.';
            } catch (Exception e) {
                res.message = 'Failed to enqueue batch: ' + e.getMessage();
            }

            out.add(res);
        }
        return out;
    }
}
