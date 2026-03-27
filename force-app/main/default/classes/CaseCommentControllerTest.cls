@IsTest
private class CaseCommentControllerTest {

    // ── Test data setup ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Create account + contact + community user
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName  = 'Customer',
            AccountId = acc.Id,
            Email     = 'testcustomer@example.invalid'
        );
        insert con;

        // Create a case owned by the contact's account
        Case c = new Case(
            Subject   = 'Test Case Subject',
            Status    = 'Open',
            AccountId = acc.Id,
            ContactId = con.Id
        );
        insert c;

        // Seed a public case comment
        CaseComment cc = new CaseComment(
            ParentId    = c.Id,
            CommentBody = 'Initial support comment',
            IsPublished = true
        );
        insert cc;
    }

    // ── getCaseInfo ──────────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseInfo_success() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseCommentController.CaseInfoWrapper info =
            CaseCommentController.getCaseInfo(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, info,              'Info wrapper should not be null');
        System.assertNotEquals(null, info.caseNumber,   'Case number should be populated');
        System.assertEquals('Open', info.status,        'Status should be Open');
        System.assertEquals('Test Case Subject', info.subject, 'Subject should match');
    }

    // ── getCaseComments ──────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseComments_returnsPublishedComments() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<CaseCommentController.CommentWrapper> comments =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        System.assertEquals(1, comments.size(), 'Should return exactly one comment');
        System.assertEquals('Initial support comment', comments[0].body, 'Body should match');
        System.assertEquals(true, comments[0].isPublished, 'Comment should be published');
        System.assertNotEquals(null, comments[0].authorName, 'Author name should be populated');
    }

    @IsTest
    static void testGetCaseComments_unpublishedExcluded() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        // Insert an unpublished comment - should NOT appear in results
        CaseComment hidden = new CaseComment(
            ParentId    = c.Id,
            CommentBody = 'Internal note',
            IsPublished = false
        );
        insert hidden;

        Test.startTest();
        List<CaseCommentController.CommentWrapper> comments =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        System.assertEquals(1, comments.size(), 'Only published comments should be returned');
    }

    // ── addCaseComment ───────────────────────────────────────────────────────

    @IsTest
    static void testAddCaseComment_success() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseCommentController.CommentWrapper result =
            CaseCommentController.addCaseComment(c.Id, 'Hello from the customer!');
        Test.stopTest();

        System.assertNotEquals(null, result,         'Result should not be null');
        System.assertNotEquals(null, result.id,      'Id should be set');
        System.assertEquals('Hello from the customer!', result.body, 'Body should match');
        System.assertEquals(true, result.isPublished, 'New comments should be published');
        System.assertNotEquals(null, result.createdDate, 'CreatedDate should be populated');
        System.assertNotEquals(null, result.authorName,  'Author name should be populated');

        // Verify it actually persisted
        List<CaseComment> persisted = [
            SELECT Id FROM CaseComment WHERE ParentId = :c.Id AND IsPublished = true
        ];
        System.assertEquals(2, persisted.size(), 'Should now have 2 published comments');
    }

    @IsTest
    static void testAddCaseComment_blankBodyThrows() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        Boolean threw = false;

        Test.startTest();
        try {
            CaseCommentController.addCaseComment(c.Id, '   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw AuraHandledException for blank body');
    }

    @IsTest
    static void testAddCaseComment_tooLongBodyThrows() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        String longBody = 'A'.repeat(4001);
        Boolean threw = false;

        Test.startTest();
        try {
            CaseCommentController.addCaseComment(c.Id, longBody);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw for body exceeding 4000 chars');
    }

    @IsTest
    static void testAddCaseComment_nullBodyThrows() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        Boolean threw = false;

        Test.startTest();
        try {
            CaseCommentController.addCaseComment(c.Id, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw for null body');
    }

    @IsTest
    static void testAddCaseComment_exactlyMaxLength() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        String maxBody = 'B'.repeat(4000);

        Test.startTest();
        CaseCommentController.CommentWrapper result =
            CaseCommentController.addCaseComment(c.Id, maxBody);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should succeed for exactly 4000 chars');
    }
}
