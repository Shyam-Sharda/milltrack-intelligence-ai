@IsTest
private class TechnicianAIChatControllerTest {

    @TestSetup
    static void createTestData() {
        Account testAccount = new Account(Name = 'MillTrack Test Account');
        insert testAccount;

        Asset testAsset = new Asset(
            Name = 'Test DWX-53DC',
            AccountId = testAccount.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-53DC'
        );
        insert testAsset;

        WorkOrder testWorkOrder = new WorkOrder(
            AccountId = testAccount.Id,
            AssetId = testAsset.Id,
            Subject = 'Technician AI Chat Test',
            Status = 'New'
        );
        insert testWorkOrder;
    }

    @IsTest
    static void sendMessageReturnsServerResponse() {
        WorkOrder testWorkOrder = [
            SELECT Id, WorkOrderNumber, AssetId
            FROM WorkOrder
            LIMIT 1
        ];

        TechnicianAIChatController.testOutputParameters = new Map<String, Object>{
            'agentResponse' => '{"value":"Test technician briefing."}',
            'sessionId' => 'new-test-session'
        };

        Test.startTest();

        TechnicianAIChatController.ChatResponse response =
            TechnicianAIChatController.sendMessage(
                testWorkOrder.Id,
                'Give me a briefing.',
                null
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            response,
            'The controller should return a response.'
        );

        System.assertEquals(
            'Test technician briefing.',
            response.message,
            'The visible agent response should be extracted.'
        );

        System.assertEquals(
            'new-test-session',
            response.sessionId,
            'A new conversation should receive its returned session ID.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                testWorkOrder.WorkOrderNumber
            ),
            'The agent prompt should identify the current Work Order.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'Give me a briefing.'
            ),
            'The agent prompt should include the submitted question.'
        );
    }

    @IsTest
    static void agentMessageIncludesMachineContext() {
        WorkOrder testWorkOrder = [
            SELECT Id
            FROM WorkOrder
            LIMIT 1
        ];

        TechnicianAIChatController.testOutputParameters = new Map<String, Object>{
            'agentResponse' => '{"value":"Manual correction procedure."}',
            'sessionId' => 'machine-context-session'
        };

        Test.startTest();

        TechnicianAIChatController.ChatResponse response =
            TechnicianAIChatController.sendMessage(
                testWorkOrder.Id,
                'What is the procedure for manual correction on this machine?',
                null
            );

        Test.stopTest();

        System.assertEquals(
            'Manual correction procedure.',
            response.message,
            'The response should be returned normally.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'Current Machine Manufacturer: Roland'
            ),
            'The prompt should provide the machine manufacturer.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'Current Machine Model: DWX-53DC'
            ),
            'The prompt should provide the machine model.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'What is the procedure for manual correction on this machine?'
            ),
            'The original technician question should remain intact.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'does not by itself mean the request is Work Order Assistance'
            ),
            'The prompt should treat Salesforce records as context rather than routing intent.'
        );

        System.assert(
            !TechnicianAIChatController.lastAgentMessage.contains(
                'Use the Current Work Order ID when invoking Work Order Assistance'
            ),
            'The previous Work Order Assistance routing bias should not be present.'
        );
    }

    @IsTest
    static void existingSessionIdIsPreserved() {
        WorkOrder testWorkOrder = [
            SELECT Id
            FROM WorkOrder
            LIMIT 1
        ];

        String existingSessionId = 'existing-test-session';

        // Some follow-up Agentforce responses omit sessionId. The controller
        // should keep using the session supplied with the request.
        TechnicianAIChatController.testOutputParameters = new Map<String, Object>{
            'agentResponse' => 'Use a torque wrench.'
        };

        Test.startTest();

        TechnicianAIChatController.ChatResponse response =
            TechnicianAIChatController.sendMessage(
                testWorkOrder.Id,
                'What tools do I need?',
                existingSessionId
            );

        Test.stopTest();

        System.assertEquals(
            existingSessionId,
            response.sessionId,
            'Follow-up messages should preserve the existing session.'
        );

        System.assertEquals(
            existingSessionId,
            TechnicianAIChatController.lastRequestedSessionId,
            'The existing session should be supplied to Agentforce.'
        );

        System.assert(
            TechnicianAIChatController.lastAgentMessage.contains(
                'What tools do I need?'
            ),
            'The follow-up prompt should include the question.'
        );
    }

    @IsTest
    static void blankMessageThrowsHandledException() {
        WorkOrder testWorkOrder = [
            SELECT Id
            FROM WorkOrder
            LIMIT 1
        ];

        Test.startTest();

        try {
            TechnicianAIChatController.sendMessage(
                testWorkOrder.Id,
                '   ',
                null
            );

            System.assert(
                false,
                'A blank message should throw an exception.'
            );
        } catch (AuraHandledException exceptionDetails) {
            System.assertNotEquals(
                null,
                exceptionDetails,
                'The exception should be handled for the LWC.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void missingWorkOrderThrowsHandledException() {
        Test.startTest();

        try {
            TechnicianAIChatController.sendMessage(
                null,
                'Give me a briefing.',
                null
            );

            System.assert(
                false,
                'A missing Work Order ID should throw an exception.'
            );
        } catch (AuraHandledException exceptionDetails) {
            System.assertNotEquals(
                null,
                exceptionDetails,
                'The exception should be handled for the LWC.'
            );
        }

        Test.stopTest();
    }
}