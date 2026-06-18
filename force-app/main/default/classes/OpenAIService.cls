public with sharing class OpenAIService {
    //backend connector, responsible for talking to OpenAI
    @AuraEnabled
    public static String askOpenAI(String prompt) {
        if(String.isBlank(prompt)) {
            return 'Please enter a question.';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OpenAI/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        Map<String, Object> message = new Map<String, Object>{
            'role' => 'user',
            'content' => prompt
        };

        Map<String, Object> body = new Map<String, Object>{
            'model' => 'gpt-4o-mini',
            'messages' => new List<Object> { message },
            'temperature' => 0.2
        };

        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('OpenAI Status Code: ' + res.getStatusCode());
        System.debug('OpenAI Response: ' + res.getBody());

        if(res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return res.getBody();
        }

        return 'OpenAI callout failed: ' + res.getBody();
    }
}