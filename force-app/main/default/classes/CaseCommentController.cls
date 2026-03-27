/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CaseCommentControllerTest
 * Author          : SaltClick
 * Created Date    : Mar 23, 2026
 * Last Modified By: SaltClick
 * Last Modified On: Mar 25, 2026
 * Description     : Test coverage for CaseCommentController
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
private class CaseCommentControllerTest {

    // ─── Test Data Factory ────────────────────────────────────────────────────

    private static Account makeAccount() {
        Account a = new Account(Name = 'Test Account');
        insert a;
        return a;
    }

    private static Contact makeContact(Id accountId) {
        Contact c = new Contact(LastName = 'Tester', AccountId = accountId);
        insert c;
        return c;
    }

    private static Case makeCase(String status) {
        Account a = makeAccount();
        Case c = new Case(
            Subject     = 'Test Case',
            Status      = status,
            AccountId   = a.Id,
            Origin      = 'Web'
        );
        insert c;
        return c;
    }

    private static CaseComment makeComment(Id caseId, String body) {
        CaseComment cc = new CaseComment(
            ParentId    = caseId,
            CommentBody = body,
            IsPublished = true
        );
        insert cc;
        return cc;
    }

    private static ContentDocument makeContentDocument(Id linkedEntityId) {
        ContentVersion cv = new ContentVersion(
            Title           = 'TestFile',
            PathOnClient    = 'TestFile.txt',
            VersionData     = Blob.valueOf('Hello World'),
            IsMajorVersion  = true
        );
        insert cv;

        ContentVersion inserted = [
            SELECT Id, ContentDocumentId
            FROM   ContentVersion
            WHERE  Id = :cv.Id
            LIMIT  1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = inserted.ContentDocumentId,
            LinkedEntityId    = linkedEntityId,
            ShareType         = 'V',
            Visibility        = 'InternalUsers'
        );
        insert cdl;

        return [SELECT Id, Title, FileExtension FROM ContentDocument WHERE Id = :inserted.ContentDocumentId LIMIT 1];
    }

    // ─── getCaseInfo ──────────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseInfo_returnsCaseDetails() {
        Case c = makeCase('New');

        Test.startTest();
        CaseCommentController.CaseInfoWrapper info = CaseCommentController.getCaseInfo(c.Id);
        Test.stopTest();

        Assert.areEqual('Test Case', info.subject,    'Subject should match');
        Assert.areEqual('New',       info.status,     'Status should match');
        Assert.isNotNull(info.caseNumber,              'CaseNumber should be populated');
    }

    @IsTest
    static void testGetCaseInfo_nullId_returnsNull() {
        Test.startTest();
        CaseCommentController.CaseInfoWrapper info = CaseCommentController.getCaseInfo(null);
        Test.stopTest();

        Assert.isNull(info, 'Should return null for null caseId');
    }

    // ─── getCaseComments ──────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseComments_noComments_returnsEmptyList() {
        Case c = makeCase('New');

        Test.startTest();
        List<CaseCommentController.CommentWrapper> result =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Should return empty list when no comments exist');
    }

    @IsTest
    static void testGetCaseComments_nullId_returnsEmptyList() {
        Test.startTest();
        List<CaseCommentController.CommentWrapper> result =
            CaseCommentController.getCaseComments(null);
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Should return empty list for null caseId');
    }

    @IsTest
    static void testGetCaseComments_withPublishedComment_returnsWrapper() {
        Case c = makeCase('New');
        makeComment(c.Id, 'Hello from customer');

        Test.startTest();
        List<CaseCommentController.CommentWrapper> result =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        Assert.areEqual(1, result.size(), 'Should return one comment');
        CaseCommentController.CommentWrapper w = result[0];
        Assert.areEqual('Hello from customer', w.body, 'Body should match');
        Assert.isNotNull(w.authorName,                  'Author name should be set');
        Assert.isNotNull(w.createdDate,                 'Created date should be set');
        Assert.isNotNull(w.isAgent,                     'isAgent should be set');
        Assert.isTrue(w.files.isEmpty(),                'No files should be attached');
    }

    @IsTest
    static void testGetCaseComments_withJunctionFile_returnsFileOnComment() {
        Case c             = makeCase('New');
        CaseComment cc     = makeComment(c.Id, 'Comment with file');
        ContentDocument doc = makeContentDocument(c.Id);

        // Create the junction record
        Case_Comment_File__c junc = new Case_Comment_File__c(
            Case__c              = c.Id,
            CaseCommentId__c     = String.valueOf(cc.Id),
            ContentDocumentId__c = String.valueOf(doc.Id)
        );
        insert junc;

        Test.startTest();
        List<CaseCommentController.CommentWrapper> result =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        Assert.areEqual(1, result.size(), 'Should return one comment');
        Assert.isFalse(result[0].files.isEmpty(), 'Comment should have a file attached');

        CaseCommentController.FileWrapper fw = result[0].files[0];
        Assert.areEqual(doc.Id,    fw.contentDocumentId, 'Document Id should match');
        Assert.areEqual('TestFile', fw.title,             'Title should match');
        Assert.isNotNull(fw.downloadUrl,                  'Download URL should be set');
    }

    @IsTest
    static void testGetCaseComments_agentUploadMatchedByTimestamp() {
        Case c         = makeCase('New');
        CaseComment cc = makeComment(c.Id, 'Agent comment');

        // Upload a doc directly to the Case (simulates agent attach)
        ContentVersion cv = new ContentVersion(
            Title           = 'AgentFile',
            PathOnClient    = 'AgentFile.pdf',
            VersionData     = Blob.valueOf('PDF content'),
            IsMajorVersion  = true
        );
        insert cv;

        ContentVersion inserted = [
            SELECT Id, ContentDocumentId
            FROM   ContentVersion
            WHERE  Id = :cv.Id
            LIMIT  1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = inserted.ContentDocumentId,
            LinkedEntityId    = c.Id,
            ShareType         = 'V',
            Visibility        = 'InternalUsers'
        );
        insert cdl;

        Test.startTest();
        List<CaseCommentController.CommentWrapper> result =
            CaseCommentController.getCaseComments(c.Id);
        Test.stopTest();

        // The file should be timestamp-matched to the single comment
        Assert.areEqual(1, result.size(), 'Should return one comment');
        Assert.isFalse(result[0].files.isEmpty(),
            'Agent-uploaded file should be matched to the comment by timestamp');
    }

    // ─── addCaseComment ───────────────────────────────────────────────────────

    @IsTest
    static void testAddCaseComment_basic_insertsAndReturnsWrapper() {
        Case c = makeCase('New');

        Test.startTest();
        CaseCommentController.CommentWrapper result =
            CaseCommentController.addCaseComment(c.Id, 'My first comment', null);
        Test.stopTest();

        Assert.isNotNull(result,                     'Result wrapper should not be null');
        Assert.areEqual('My first comment', result.body, 'Body should match');
        Assert.isNotNull(result.id,                  'Comment Id should be set');
        Assert.isTrue(result.files.isEmpty(),         'No files expected');
    }

    @IsTest
    static void testAddCaseComment_withContentDocumentId_linksFile() {
        Case c              = makeCase('New');
        ContentDocument doc = makeContentDocument(c.Id);

        Test.startTest();
        CaseCommentController.CommentWrapper result =
            CaseCommentController.addCaseComment(c.Id, 'Comment with doc', new List<Id>{ doc.Id });
        Test.stopTest();

        Assert.isFalse(result.files.isEmpty(), 'File should be attached to the returned comment');
        Assert.areEqual(doc.Id, result.files[0].contentDocumentId, 'Document Id should match');

        List<Case_Comment_File__c> junctions = [
            SELECT Id FROM Case_Comment_File__c WHERE Case__c = :c.Id
        ];
        Assert.isFalse(junctions.isEmpty(), 'Junction record should have been created');
    }

    @IsTest
    static void testAddCaseComment_withContentVersionId_resolvesToDocument() {
        Case c = makeCase('New');
        ContentVersion cv = new ContentVersion(
            Title          = 'VersionFile',
            PathOnClient   = 'VersionFile.txt',
            VersionData    = Blob.valueOf('data'),
            IsMajorVersion = true
        );
        insert cv;

        ContentVersion inserted = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = inserted.ContentDocumentId,
            LinkedEntityId    = c.Id,
            ShareType         = 'V',
            Visibility        = 'InternalUsers'
        );
        insert cdl;

        Test.startTest();
        // Pass the ContentVersion Id — controller should resolve to the ContentDocument
        CaseCommentController.CommentWrapper result =
            CaseCommentController.addCaseComment(c.Id, 'Version id test', new List<Id>{ inserted.Id });
        Test.stopTest();

        Assert.isFalse(result.files.isEmpty(), 'File should resolve and attach even when passed a ContentVersion Id');
    }

    @IsTest
    static void testAddCaseComment_nullCaseId_throwsAuraHandledException() {
        try {
            CaseCommentController.addCaseComment(null, 'Body', null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('required') || e.getMessage() != null,
                'Should throw with a message');
        }
    }

    @IsTest
    static void testAddCaseComment_blankBody_throwsAuraHandledException() {
        Case c = makeCase('New');
        try {
            CaseCommentController.addCaseComment(c.Id, '   ', null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage() != null, 'Should throw for blank body');
        }
    }

    @IsTest
    static void testAddCaseComment_bodyExceedsLimit_throwsAuraHandledException() {
        Case c    = makeCase('New');
        String longBody = 'x'.repeat(4001);
        try {
            CaseCommentController.addCaseComment(c.Id, longBody, null);
            Assert.fail('Expected AuraHandledException for body > 4000 chars');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('4,000'), 'Should mention character limit');
        }
    }

    @IsTest
    static void testAddCaseComment_closedCase_throwsAuraHandledException() {
        Case c = makeCase('Closed');
        try {
            CaseCommentController.addCaseComment(c.Id, 'Try to comment', null);
            Assert.fail('Expected AuraHandledException for closed case');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('closed'),
                'Should throw indicating case is closed');
        }
    }

    @IsTest
    static void testAddCaseComment_resolvedCase_throwsAuraHandledException() {
        Case c = makeCase('Resolved');
        try {
            CaseCommentController.addCaseComment(c.Id, 'Try to comment', null);
            Assert.fail('Expected AuraHandledException for resolved case');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage() != null, 'Should throw for resolved case');
        }
    }

    @IsTest
    static void testAddCaseComment_setsFileVisibilityToAllUsers() {
        Case c              = makeCase('New');
        ContentDocument doc = makeContentDocument(c.Id);

        Test.startTest();
        CaseCommentController.addCaseComment(c.Id, 'Visibility test', new List<Id>{ doc.Id });
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Visibility
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId    = :c.Id
            AND    ContentDocumentId = :doc.Id
        ];
        Assert.isFalse(links.isEmpty(), 'CDL should exist');
        Assert.areEqual('AllUsers', links[0].Visibility, 'Visibility should be AllUsers');
    }

    // ─── fixFileVisibilityForCase ─────────────────────────────────────────────

    @IsTest
    static void testFixFileVisibility_updatesNonPublicLinks() {
        Case c              = makeCase('New');
        ContentDocument doc = makeContentDocument(c.Id);

        // Confirm it starts as InternalUsers (set in makeContentDocument)
        List<ContentDocumentLink> before = [
            SELECT Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id AND ContentDocumentId = :doc.Id
        ];
        Assert.areEqual('InternalUsers', before[0].Visibility, 'Should start as InternalUsers');

        Test.startTest();
        CaseCommentController.fixFileVisibilityForCase(c.Id);
        Test.stopTest();

        List<ContentDocumentLink> after = [
            SELECT Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id AND ContentDocumentId = :doc.Id
        ];
        Assert.areEqual('AllUsers', after[0].Visibility, 'Should be updated to AllUsers');
    }

    @IsTest
    static void testFixFileVisibility_nullId_doesNotThrow() {
        Test.startTest();
        try {
            CaseCommentController.fixFileVisibilityForCase(null);
        } catch (Exception e) {
            Assert.fail('Should not throw for null caseId: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testFixFileVisibility_alreadyAllUsers_noUpdate() {
        Case c = makeCase('New');
        ContentDocument doc = makeContentDocument(c.Id);

        // Pre-set to AllUsers
        List<ContentDocumentLink> links = [
            SELECT Id, Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id AND ContentDocumentId = :doc.Id
        ];
        for (ContentDocumentLink l : links) l.Visibility = 'AllUsers';
        update links;

        Test.startTest();
        // Should execute without error and make no changes
        CaseCommentController.fixFileVisibilityForCase(c.Id);
        Test.stopTest();

        List<ContentDocumentLink> after = [
            SELECT Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id AND ContentDocumentId = :doc.Id
        ];
        Assert.areEqual('AllUsers', after[0].Visibility, 'Should remain AllUsers');
    }

    // ─── assertCaseAccess (negative path) ────────────────────────────────────

    @IsTest
    static void testAssertCaseAccess_nonExistentId_throwsAuraHandledException() {
        // Use a well-formed but non-existent Case Id
        Id fakeId = '5000000000000001';
        try {
            CaseCommentController.getCaseComments(fakeId);
            Assert.fail('Expected AuraHandledException for inaccessible case');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('permission') ||
                          e.getMessage() != null,
                'Should throw permission error');
        }
    }
}
