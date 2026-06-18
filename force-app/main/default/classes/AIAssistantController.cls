public with sharing class AIAssistantController {
    //Salesforce bridge between UI and OpenAI
    @AuraEnabled
    public static String askAssistant(String userMessage) {
        if(String.isBlank(userMessage)) {
            return 'Please enter a question.';
        }

        String systemContext = 
            'You are MillTrack Intelligence, an AI assistant for dental milling machine service support. ' +
            'Help customers, service managers, and technicians troubleshoot machine issues. ' +
            'Give clear, safe, step-by-step guidance. ' +
            'If the issue may require advanced repair, recommend escalating to a technician.';

        String finalPrompt = systemContext + '\n\nUser question:\n' + userMessage;

        return OpenAIService.askOpenAI(finalPrompt);
    } 
}