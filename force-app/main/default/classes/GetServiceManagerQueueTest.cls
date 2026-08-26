@IsTest
private class GetServiceManagerQueueTest {

    @IsTest
    static void testQueueResolvedSuccessfully() {

        Group serviceManagerQueue = new Group(
            Name = 'Test Service Manager Queue',
            DeveloperName = 'Test_Service_Manager_Queue',
            Type = 'Queue'
        );
        insert serviceManagerQueue;

        QueueSobject caseQueueMapping = new QueueSobject(
            QueueId = serviceManagerQueue.Id,
            SobjectType = 'Case'
        );
        insert caseQueueMapping;

        GetServiceManagerQueue.Request request =
            new GetServiceManagerQueue.Request();

        request.queueDeveloperName = 'Test_Service_Manager_Queue';

        Test.startTest();

        List<GetServiceManagerQueue.Result> results =
            GetServiceManagerQueue.getQueue(
                new List<GetServiceManagerQueue.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            results.size(),
            'Exactly one result should be returned.'
        );

        System.assertEquals(
            true,
            results[0].success,
            'The queue should resolve successfully.'
        );

        System.assertEquals(
            'SUCCESS',
            results[0].statusCode,
            'The status code should indicate success.'
        );

        System.assertEquals(
            String.valueOf(serviceManagerQueue.Id),
            results[0].queueId,
            'The returned queue Id should match the created queue.'
        );

        System.assertEquals(
            'Service Manager Queue resolved successfully.',
            results[0].statusMessage,
            'The expected success message should be returned.'
        );
    }


    @IsTest
    static void testQueueNotFound() {

        GetServiceManagerQueue.Request request =
            new GetServiceManagerQueue.Request();

        request.queueDeveloperName = 'Queue_That_Does_Not_Exist';

        Test.startTest();

        List<GetServiceManagerQueue.Result> results =
            GetServiceManagerQueue.getQueue(
                new List<GetServiceManagerQueue.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());

        System.assertEquals(
            false,
            results[0].success
        );

        System.assertEquals(
            'QUEUE_NOT_FOUND',
            results[0].statusCode
        );

        System.assertEquals(
            null,
            results[0].queueId,
            'No queue Id should be returned when the queue does not exist.'
        );
    }


    @IsTest
    static void testQueueDoesNotSupportCase() {

        Group nonCaseQueue = new Group(
            Name = 'Test Non Case Queue',
            DeveloperName = 'Test_Non_Case_Queue',
            Type = 'Queue'
        );
        insert nonCaseQueue;

        GetServiceManagerQueue.Request request =
            new GetServiceManagerQueue.Request();

        request.queueDeveloperName = 'Test_Non_Case_Queue';

        Test.startTest();

        List<GetServiceManagerQueue.Result> results =
            GetServiceManagerQueue.getQueue(
                new List<GetServiceManagerQueue.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());

        System.assertEquals(
            false,
            results[0].success
        );

        System.assertEquals(
            'QUEUE_DOES_NOT_SUPPORT_CASE',
            results[0].statusCode
        );

        System.assertEquals(
            null,
            results[0].queueId
        );
    }


    @IsTest
    static void testMissingQueueDeveloperName() {

        GetServiceManagerQueue.Request request =
            new GetServiceManagerQueue.Request();

        request.queueDeveloperName = null;

        Test.startTest();

        List<GetServiceManagerQueue.Result> results =
            GetServiceManagerQueue.getQueue(
                new List<GetServiceManagerQueue.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());

        System.assertEquals(
            false,
            results[0].success
        );

        System.assertEquals(
            'MISSING_QUEUE_NAME',
            results[0].statusCode
        );

        System.assertEquals(
            null,
            results[0].queueId
        );
    }


    @IsTest
    static void testBlankQueueDeveloperName() {

        GetServiceManagerQueue.Request request =
            new GetServiceManagerQueue.Request();

        request.queueDeveloperName = '   ';

        Test.startTest();

        List<GetServiceManagerQueue.Result> results =
            GetServiceManagerQueue.getQueue(
                new List<GetServiceManagerQueue.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());

        System.assertEquals(
            false,
            results[0].success
        );

        System.assertEquals(
            'MISSING_QUEUE_NAME',
            results[0].statusCode
        );
    }
}