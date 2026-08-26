@IsTest
private class CreateAuthorizedCaseCommentTest {

    @TestSetup
    static void setupData() {
        Account accountOne = new Account(
            Name = 'Case Comment Test Account 1'
        );

        Account accountTwo = new Account(
            Name = 'Case Comment Test Account 2'
        );

        insert new List<Account>{ accountOne, accountTwo };

        Contact contactOne = new Contact(
            FirstName = 'Authorized',
            LastName = 'Customer',
            AccountId = accountOne.Id
        );

        Contact contactTwoSameAccount = new Contact(
            FirstName = 'Wrong',
            LastName = 'Customer',
            AccountId = accountOne.Id
        );

        Contact contactThreeOtherAccount = new Contact(
            FirstName = 'Other',
            LastName = 'Account Customer',
            AccountId = accountTwo.Id
        );

        insert new List<Contact>{
            contactOne,
            contactTwoSameAccount,
            contactThreeOtherAccount
        };

        String openStatus = getCaseStatus(false);
        String closedStatus = getCaseStatus(true);
        String caseOrigin = getActivePicklistValue(Schema.SObjectType.Case.fields.Origin, 'Web');

        Case openCase = new Case(
            Subject = 'Authorized Open Case',
            Status = openStatus,
            Origin = caseOrigin,
            AccountId = accountOne.Id,
            ContactId = contactOne.Id
        );

        Case closedCase = new Case(
            Subject = 'Authorized Closed Case',
            Status = closedStatus,
            Origin = caseOrigin,
            AccountId = accountOne.Id,
            ContactId = contactOne.Id
        );

        insert new List<Case>{ openCase, closedCase };
    }

    @IsTest
    static void authorizedOpenCaseCreatesComment() {
        Contact authorizedContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE FirstName = 'Authorized'
            AND LastName = 'Customer'
            LIMIT 1
        ];

        Case openCase = [
            SELECT Id, CaseNumber, ContactId, AccountId, IsClosed
            FROM Case
            WHERE Subject = 'Authorized Open Case'
            LIMIT 1
        ];

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = openCase.Id;
        request.verifiedContactId = authorizedContact.Id;
        request.commentBody =
            'Authorized customer regression test comment.';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            responses.size(),
            'Exactly one response should be returned.'
        );

        System.assertEquals(
            true,
            responses[0].success,
            'Authorized open Case should allow comment creation.'
        );

        System.assertEquals(
            'COMMENT_CREATED',
            responses[0].statusCode
        );

        System.assertNotEquals(
            null,
            responses[0].caseCommentId,
            'Successful response should return the Case Comment Id.'
        );

        System.assertEquals(
            openCase.CaseNumber,
            responses[0].caseNumber,
            'Successful response should return the authorized Case Number.'
        );

        CaseComment createdComment = [
            SELECT Id, ParentId, CommentBody, IsPublished
            FROM CaseComment
            WHERE Id = :responses[0].caseCommentId
            LIMIT 1
        ];

        System.assertEquals(
            openCase.Id,
            createdComment.ParentId
        );

        System.assertEquals(
            'Authorized customer regression test comment.',
            createdComment.CommentBody
        );

        System.assertEquals(
            true,
            createdComment.IsPublished
        );
    }

    @IsTest
    static void wrongContactIsBlocked() {
        Contact wrongContact = [
            SELECT Id
            FROM Contact
            WHERE FirstName = 'Wrong'
            AND LastName = 'Customer'
            LIMIT 1
        ];

        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Authorized Open Case'
            LIMIT 1
        ];

        Integer commentsBefore = [
            SELECT COUNT()
            FROM CaseComment
            WHERE ParentId = :openCase.Id
        ];

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = openCase.Id;
        request.verifiedContactId = wrongContact.Id;
        request.commentBody = 'This should not be created.';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'CASE_NOT_AUTHORIZED',
            responses[0].statusCode
        );

        Integer commentsAfter = [
            SELECT COUNT()
            FROM CaseComment
            WHERE ParentId = :openCase.Id
        ];

        System.assertEquals(
            commentsBefore,
            commentsAfter,
            'Unauthorized Contact must not create a Case Comment.'
        );
    }

    @IsTest
    static void differentAccountIsBlocked() {
        Contact otherAccountContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE FirstName = 'Other'
            AND LastName = 'Account Customer'
            LIMIT 1
        ];

        Case openCase = [
            SELECT Id, AccountId
            FROM Case
            WHERE Subject = 'Authorized Open Case'
            LIMIT 1
        ];

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = openCase.Id;
        request.verifiedContactId = otherAccountContact.Id;
        request.commentBody =
            'Cross-account comment should not be created.';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'CASE_NOT_AUTHORIZED',
            responses[0].statusCode
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM CaseComment
                WHERE ParentId = :openCase.Id
                AND CommentBody =
                    'Cross-account comment should not be created.'
            ],
            'A customer from another Account must not add a comment.'
        );
    }

    @IsTest
    static void closedCaseIsBlocked() {
        Contact authorizedContact = [
            SELECT Id
            FROM Contact
            WHERE FirstName = 'Authorized'
            AND LastName = 'Customer'
            LIMIT 1
        ];

        Case closedCase = [
            SELECT Id, IsClosed
            FROM Case
            WHERE Subject = 'Authorized Closed Case'
            LIMIT 1
        ];

        System.assertEquals(
            true,
            closedCase.IsClosed,
            'Test Case must actually be closed.'
        );

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = closedCase.Id;
        request.verifiedContactId = authorizedContact.Id;
        request.commentBody =
            'Closed Case comment should not be created.';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'CASE_CLOSED',
            responses[0].statusCode
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM CaseComment
                WHERE ParentId = :closedCase.Id
            ],
            'Closed Case must not receive a customer comment.'
        );
    }

    @IsTest
    static void blankCommentIsBlocked() {
        Contact authorizedContact = [
            SELECT Id
            FROM Contact
            WHERE FirstName = 'Authorized'
            AND LastName = 'Customer'
            LIMIT 1
        ];

        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Authorized Open Case'
            LIMIT 1
        ];

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = openCase.Id;
        request.verifiedContactId = authorizedContact.Id;
        request.commentBody = '   ';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'INVALID_REQUEST',
            responses[0].statusCode
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM CaseComment
                WHERE ParentId = :openCase.Id
            ],
            'Blank text must not create a Case Comment.'
        );
    }

    @IsTest
    static void missingCaseIdIsBlocked() {
        Contact authorizedContact = [
            SELECT Id
            FROM Contact
            WHERE FirstName = 'Authorized'
            AND LastName = 'Customer'
            LIMIT 1
        ];

        CreateAuthorizedCaseComment.Request request =
            new CreateAuthorizedCaseComment.Request();

        request.caseId = null;
        request.verifiedContactId = authorizedContact.Id;
        request.commentBody = 'Missing Case test.';

        Test.startTest();

        List<CreateAuthorizedCaseComment.Response> responses =
            CreateAuthorizedCaseComment.createComments(
                new List<CreateAuthorizedCaseComment.Request>{ request }
            );

        Test.stopTest();

        System.assertEquals(false, responses[0].success);

        System.assertEquals(
            'INVALID_REQUEST',
            responses[0].statusCode
        );
    }

    private static String getCaseStatus(Boolean shouldBeClosed) {
        List<CaseStatus> statuses = [
            SELECT MasterLabel, IsClosed
            FROM CaseStatus
            WHERE IsClosed = :shouldBeClosed
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A Case Status matching closed=' +
            shouldBeClosed +
            ' must exist in the org.'
        );

        return statuses[0].MasterLabel;
    }

    private static String getActivePicklistValue(
        Schema.DescribeFieldResult fieldDescribe,
        String preferredValue
    ) {
        List<Schema.PicklistEntry> entries =
            fieldDescribe.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (
                entry.isActive() &&
                entry.getValue() == preferredValue
            ) {
                return entry.getValue();
            }
        }

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}