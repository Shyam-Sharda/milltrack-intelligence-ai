public without sharing class GetServiceManagerQueue {

    public class Request {
        @InvocableVariable(
            label='Queue Developer Name'
            description='Developer Name of the queue to resolve.'
            required=true
        )
        public String queueDeveloperName;
    }

    public class Result {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String statusCode;

        @InvocableVariable
        public String queueId;

        @InvocableVariable
        public String statusMessage;
    }

    @InvocableMethod(
        label='Get Service Manager Queue'
        description='Resolves an internal Salesforce queue by Developer Name and confirms that it supports Case ownership.'
    )
    public static List<Result> getQueue(List<Request> requests) {

        List<Result> results = new List<Result>();

        for (Request request : requests) {
            Result result = new Result();
            result.success = false;

            if (
                request == null ||
                String.isBlank(request.queueDeveloperName)
            ) {
                result.statusCode = 'MISSING_QUEUE_NAME';
                result.statusMessage =
                    'A queue developer name was not provided.';
                results.add(result);
                continue;
            }

            /*
             * Intentional system-mode lookup.
             *
             * CUST 02 runs as the authenticated Experience Cloud customer.
             * That user should not require direct access to Salesforce
             * Group / Queue setup data merely to route a service Case.
             */
            List<Group> queues = [
                SELECT Id, DeveloperName, Type
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName = :request.queueDeveloperName
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (queues.isEmpty()) {
                result.statusCode = 'QUEUE_NOT_FOUND';
                result.statusMessage =
                    'The requested service queue could not be found.';
                results.add(result);
                continue;
            }

            Group serviceQueue = queues[0];

            /*
             * Confirm that the resolved queue is actually configured
             * to own Case records.
             */
            List<QueueSobject> caseQueueMappings = [
                SELECT Id, QueueId, SobjectType
                FROM QueueSobject
                WHERE QueueId = :serviceQueue.Id
                AND SobjectType = 'Case'
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (caseQueueMappings.isEmpty()) {
                result.statusCode = 'QUEUE_DOES_NOT_SUPPORT_CASE';
                result.statusMessage =
                    'The requested service queue is not configured to own Cases.';
                results.add(result);
                continue;
            }

            result.success = true;
            result.statusCode = 'SUCCESS';
            result.queueId = serviceQueue.Id;
            result.statusMessage =
                'Service Manager Queue resolved successfully.';

            results.add(result);
        }

        return results;
    }
}