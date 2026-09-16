List<Maintenance_Log__c> logsToUpdate = new List<Maintenance_Log__c>();

for (Maintenance_Log__c logRecord : [
    SELECT Id, Problem_Summary__c, Work_Order__c, Work_Order__r.Problem_Summary__c
    FROM Maintenance_Log__c
    WHERE Work_Order__c != null
]) {
    if (
        logRecord.Work_Order__r != null &&
        !String.isBlank(logRecord.Work_Order__r.Problem_Summary__c)
    ) {
        logRecord.Problem_Summary__c =
            logRecord.Work_Order__r.Problem_Summary__c.trim();

        logsToUpdate.add(logRecord);
    }
}

if (!logsToUpdate.isEmpty()) {
    update logsToUpdate;
}

System.debug(
    LoggingLevel.INFO,
    'Maintenance Logs synchronized: ' + logsToUpdate.size()
);