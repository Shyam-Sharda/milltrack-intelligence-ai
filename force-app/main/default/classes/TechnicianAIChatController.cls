public with sharing class TechnicianAIChatController {
    private static final String AGENT_API_NAME =
        'MillTrack_Technician_Agent';
    private static final Integer MAX_MESSAGE_LENGTH = 4000;

    /**
     * Test-only seam for deterministic Agentforce output. Production requests
     * continue to invoke the configured Agentforce agent.
     */
    @TestVisible
    private static Map<String, Object> testOutputParameters;

    @TestVisible
    private static String lastAgentMessage;

    @TestVisible
    private static String lastRequestedSessionId;

    @AuraEnabled
    public static ChatResponse sendMessage(
        Id workOrderId,
        String userMessage,
        String sessionId
    ) {
        validateRequest(workOrderId, userMessage);

        WorkOrder currentWorkOrder =
            getAccessibleWorkOrder(workOrderId);
        String agentMessage = buildAgentMessage(
            currentWorkOrder,
            userMessage.trim()
        );

        lastAgentMessage = agentMessage;
        lastRequestedSessionId = sessionId;

        try {
            if (
                Test.isRunningTest() &&
                testOutputParameters != null
            ) {
                return processAgentOutput(
                    testOutputParameters,
                    sessionId
                );
            }

            Invocable.Action agentAction =
                Invocable.Action.createCustomAction(
                    'generateAiAgentResponse',
                    AGENT_API_NAME
                );

            agentAction.setInvocationParameter(
                'userMessage',
                agentMessage
            );

            // Salesforce creates the ID for a new conversation.
            if (String.isNotBlank(sessionId)) {
                agentAction.setInvocationParameter(
                    'sessionId',
                    sessionId
                );
            }

            List<Invocable.Action.Result> results =
                agentAction.invoke();

            return processAgentResult(results, sessionId);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception exceptionDetails) {
            System.debug(
                LoggingLevel.ERROR,
                'Technician AI invocation failed: ' +
                exceptionDetails.getMessage()
            );

            throw new AuraHandledException(
                'Technician AI could not complete the request. ' +
                'Please try again.'
            );
        }
    }

    private static WorkOrder getAccessibleWorkOrder(
        Id workOrderId
    ) {
        try {
            return [
                SELECT
                    Id,
                    WorkOrderNumber,
                    Subject,
                    Dispatch_Status__c,
                    AssetId,
                    CaseId
                FROM WorkOrder
                WHERE Id = :workOrderId
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (QueryException exceptionDetails) {
            throw new AuraHandledException(
                'The current Work Order could not be accessed. ' +
                'Confirm that you have permission to view it.'
            );
        }
    }

    private static String buildAgentMessage(
        WorkOrder currentWorkOrder,
        String technicianQuestion
    ) {
        List<String> contextLines = new List<String>{
            'SYSTEM-PROVIDED SALESFORCE RECORD CONTEXT',
            '',
            'Current Work Order ID: ' +
                String.valueOf(currentWorkOrder.Id),
            'Current Work Order Number: ' +
                currentWorkOrder.WorkOrderNumber
        };

        if (String.isNotBlank(currentWorkOrder.Subject)) {
            contextLines.add(
                'Current Work Order Subject: ' +
                currentWorkOrder.Subject
            );
        }

        if (
            String.isNotBlank(
                currentWorkOrder.Dispatch_Status__c
            )
        ) {
            contextLines.add(
                'Current Dispatch Status: ' +
                currentWorkOrder.Dispatch_Status__c
            );
        }

        if (currentWorkOrder.AssetId != null) {
            contextLines.add(
                'Current Asset ID: ' +
                String.valueOf(currentWorkOrder.AssetId)
            );
        }

        if (currentWorkOrder.CaseId != null) {
            contextLines.add(
                'Current Case ID: ' +
                String.valueOf(currentWorkOrder.CaseId)
            );
        }

        contextLines.add('');
        contextLines.add(
            'Use the Current Work Order ID when invoking Work Order ' +
            'Assistance or any Salesforce grounding action.'
        );
        contextLines.add('');
        contextLines.add('TECHNICIAN QUESTION');
        contextLines.add(technicianQuestion);

        return String.join(contextLines, '\n');
    }

    private static ChatResponse processAgentResult(
        List<Invocable.Action.Result> results,
        String requestedSessionId
    ) {
        if (results == null || results.isEmpty()) {
            throw new AuraHandledException(
                'Technician AI returned no result.'
            );
        }

        Invocable.Action.Result result = results[0];

        if (!result.isSuccess()) {
            System.debug(
                LoggingLevel.ERROR,
                'Technician AI action errors: ' +
                String.valueOf(result.getErrors())
            );

            throw new AuraHandledException(
                'Technician AI was unable to answer the request.'
            );
        }

        return processAgentOutput(
            result.getOutputParameters(),
            requestedSessionId
        );
    }

    private static ChatResponse processAgentOutput(
        Map<String, Object> outputParameters,
        String requestedSessionId
    ) {
        if (outputParameters == null) {
            throw new AuraHandledException(
                'Technician AI returned no output.'
            );
        }

        Object agentResponseValue =
            outputParameters.get('agentResponse');

        if (agentResponseValue == null) {
            throw new AuraHandledException(
                'Technician AI returned an empty response.'
            );
        }

        ChatResponse response = new ChatResponse();
        response.message = extractAgentText(agentResponseValue);

        if (String.isBlank(response.message)) {
            throw new AuraHandledException(
                'Technician AI returned an empty response.'
            );
        }

        Object returnedSessionId =
            outputParameters.get('sessionId');
        String returnedSessionText =
            returnedSessionId == null
            ? null
            : String.valueOf(returnedSessionId);

        response.sessionId =
            String.isNotBlank(returnedSessionText)
            ? returnedSessionText
            : requestedSessionId;

        return response;
    }

    private static void validateRequest(
        Id workOrderId,
        String userMessage
    ) {
        if (workOrderId == null) {
            throw new AuraHandledException(
                'A Work Order ID was not supplied to Technician AI.'
            );
        }

        if (
            workOrderId.getSObjectType() !=
            WorkOrder.SObjectType
        ) {
            throw new AuraHandledException(
                'The supplied record ID is not a Work Order.'
            );
        }

        if (String.isBlank(userMessage)) {
            throw new AuraHandledException(
                'Enter a question before sending your message.'
            );
        }

        if (userMessage.length() > MAX_MESSAGE_LENGTH) {
            throw new AuraHandledException(
                'Your message is too long. Keep it below ' +
                MAX_MESSAGE_LENGTH +
                ' characters.'
            );
        }
    }

    private static String extractAgentText(
        Object agentResponseValue
    ) {
        if (agentResponseValue == null) {
            return null;
        }

        if (
            agentResponseValue instanceof Map<String, Object>
        ) {
            Map<String, Object> responseEnvelope =
                (Map<String, Object>) agentResponseValue;
            Object envelopeValue = responseEnvelope.get('value');

            if (
                envelopeValue != null &&
                String.isNotBlank(String.valueOf(envelopeValue))
            ) {
                return String.valueOf(envelopeValue).trim();
            }
        }

        String rawResponse =
            String.valueOf(agentResponseValue).trim();

        if (String.isBlank(rawResponse)) {
            return null;
        }

        if (
            rawResponse.startsWith('{') &&
            rawResponse.endsWith('}')
        ) {
            try {
                Map<String, Object> responseEnvelope =
                    (Map<String, Object>)
                    JSON.deserializeUntyped(rawResponse);
                Object value = responseEnvelope.get('value');

                if (
                    value != null &&
                    String.isNotBlank(String.valueOf(value))
                ) {
                    return String.valueOf(value).trim();
                }
            } catch (JSONException parseException) {
                System.debug(
                    LoggingLevel.WARN,
                    'Agent response was not a recognized JSON envelope: ' +
                    parseException.getMessage()
                );
            }
        }

        return rawResponse;
    }

    public class ChatResponse {
        @AuraEnabled
        public String message { get; set; }

        @AuraEnabled
        public String sessionId { get; set; }
    }
}
