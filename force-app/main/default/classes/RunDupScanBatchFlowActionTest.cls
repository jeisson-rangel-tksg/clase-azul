@IsTest
private class RunDupScanBatchFlowActionTest {
    @IsTest
    static void enqueues_batch_created_today() {
        RunDupScanBatchFlowAction.Request req = new RunDupScanBatchFlowAction.Request();
        req.threshold = 2;
        req.batchSize = 50;
        req.ruleDeveloperNames = new List<String>();

        Test.startTest();
        List<RunDupScanBatchFlowAction.Result> rs =
            RunDupScanBatchFlowAction.run(new List<RunDupScanBatchFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, rs.size());
        System.assertEquals(true, rs[0].success);
        System.assertNotEquals(null, rs[0].jobId);
        System.assertEquals('CreatedToday', rs[0].mode);
    }
}
