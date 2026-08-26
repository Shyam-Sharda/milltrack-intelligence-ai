public without sharing class CreateAuthorizedCaseComment {

    public class Request {
        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable(required=true)
        public Id verifiedContactId;

        @InvocableVariable(required=true)
        public String commentBody;
    }

    public class Response {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String statusCode;

        @InvocableVariable
        public String statusMessage;

        @InvocableVariable
        public Id caseCommentId;

        @InvocableVariable
        public String caseNumber;
    }

    @InvocableMethod(
        label='Create Authorized Case Comment'
        description='Securely verifies an authenticated customer Case and creates a public Case Comment.'
    )
    public static List<Response> createComments(List<Request> requests) {

        List<Response> responses = new List<Response>();

        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {

            Response res = new Response();
            res.success = false;

            try {
                // Validate required input.
                if (
                    req == null ||
                    req.caseId == null ||
                    req.verifiedContactId == null ||
                    String.isBlank(req.commentBody)
                ) {
                    res.statusCode = 'INVALID_REQUEST';
                    res.statusMessage =
                        'Case, verified Contact, and comment text are required.';
                    responses.add(res);
                    continue;
                }

                // Retrieve the trusted Contact explicitly in system mode.
                List<Contact> contacts = [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Id = :req.verifiedContactId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];

                if (contacts.isEmpty()) {
                    res.statusCode = 'INVALID_VERIFIED_CONTACT';
                    res.statusMessage =
                        'The verified customer Contact could not be found.';
                    responses.add(res);
                    continue;
                }

                Contact verifiedContact = contacts[0];

                if (verifiedContact.AccountId == null) {
                    res.statusCode = 'INVALID_VERIFIED_CONTACT';
                    res.statusMessage =
                        'The verified customer Contact is not associated with an Account.';
                    responses.add(res);
                    continue;
                }

                // Retrieve the requested Case explicitly in system mode.
                List<Case> cases = [
                    SELECT Id, CaseNumber, ContactId, AccountId, IsClosed
                    FROM Case
                    WHERE Id = :req.caseId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];

                if (cases.isEmpty()) {
                    res.statusCode = 'CASE_NOT_FOUND';
                    res.statusMessage =
                        'The requested Case could not be found.';
                    responses.add(res);
                    continue;
                }

                Case serviceCase = cases[0];

                // Never trust CaseId alone. Re-authorize the Case.
                if (
                    serviceCase.ContactId != verifiedContact.Id ||
                    serviceCase.AccountId != verifiedContact.AccountId
                ) {
                    res.statusCode = 'CASE_NOT_AUTHORIZED';
                    res.statusMessage =
                        'The Case is not authorized for the verified customer.';
                    responses.add(res);
                    continue;
                }

                res.caseNumber = serviceCase.CaseNumber;

                if (serviceCase.IsClosed) {
                    res.statusCode = 'CASE_CLOSED';
                    res.statusMessage =
                        'Closed Cases cannot receive customer updates.';
                    responses.add(res);
                    continue;
                }

                CaseComment newComment = new CaseComment(
                    ParentId = serviceCase.Id,
                    CommentBody = req.commentBody.trim(),
                    IsPublished = true
                );

                Database.SaveResult insertResult =
                    Database.insert(
                        newComment,
                        false,
                        AccessLevel.SYSTEM_MODE
                    );

                if (insertResult.isSuccess()) {
                    res.success = true;
                    res.statusCode = 'COMMENT_CREATED';
                    res.statusMessage =
                        'The Case comment was created successfully.';
                    res.caseCommentId = insertResult.getId();
                } else {
                    res.statusCode = 'SYSTEM_ERROR';
                    res.statusMessage =
                        'The Case comment could not be created.';

                    if (!insertResult.getErrors().isEmpty()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'CreateAuthorizedCaseComment DML error: ' +
                            insertResult.getErrors()[0].getStatusCode() +
                            ' - ' +
                            insertResult.getErrors()[0].getMessage()
                        );
                    }
                }

            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'CreateAuthorizedCaseComment exception: ' +
                    e.getTypeName() + ' - ' + e.getMessage()
                );

                res.statusCode = 'SYSTEM_ERROR';
                res.statusMessage =
                    'The Case comment could not be created.';
            }

            responses.add(res);
        }

        return responses;
    }
}