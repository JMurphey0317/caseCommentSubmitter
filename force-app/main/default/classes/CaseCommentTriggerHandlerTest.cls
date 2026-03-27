/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CaseCommentTriggerHandlerTest
 * Author          : SaltClick
 * Created Date    : Mar 27, 2026
 * Last Modified By: SaltClick
 * Last Modified On: Mar 27, 2026
 * Description     : Test coverage for CaseCommentTriggerHandler + CaseCommentTrigger
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 27, 2026  │ SaltClick   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
private class CaseCommentTriggerHandlerTest {

    // ─── Test Data Factory ────────────────────────────────────────────────────

    private static Case makeCase(String status) {
        Account a = new Account(Name = 'Trigger Test Account');
        insert a;
        Case c = new Case(
            Subject   = 'Trigger Test Case',
            Status    = status,
            AccountId = a.Id,
            Origin    = 'Web'
        );
        insert c;
        return c;
    }

    private static CaseComment insertComment(Id caseId, String body) {
        CaseComment cc = new CaseComment(
            ParentId    = caseId,
            CommentBody = body,
            IsPublished = true
        );
        insert cc;
        return cc;
    }

    // ─── Agent comment → "Waiting on Customer" ────────────────────────────────

    @IsTest
    static void testAgentComment_setsWaitingOnCustomer() {
        // The running user in a test context has an internal profile,
        // so deriveIsAgent() returns true → status should go to "Waiting on Customer"
        Case c = makeCase('New');

        Test.startTest();
        insertComment(c.Id, 'Agent reply here');
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        Assert.areEqual('Waiting on Customer', updated.Status,
            'Internal user comment should set status to Waiting on Customer');
    }

    @IsTest
    static void testAgentComment_alreadyWaitingOnCustomer_noUpdate() {
        Case c = makeCase('Waiting on Customer');

        Test.startTest();
        insertComment(c.Id, 'Another agent reply');
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        Assert.areEqual('Waiting on Customer', updated.Status,
            'Status should remain Waiting on Customer');
    }

    // ─── Closed / Resolved cases — status must NOT change ────────────────────

    @IsTest
    static void testClosedCase_commentDoesNotChangeStatus() {
        Case c = makeCase('Closed');

        Test.startTest();
        // CaseComment on a closed case is allowed by the trigger handler
        // (the controller blocks it, but the trigger must also be safe)
        CaseComment cc = new CaseComment(
            ParentId    = c.Id,
            CommentBody = 'Comment on closed case',
            IsPublished = true
        );
        insert cc;
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        Assert.areEqual('Closed', updated.Status,
            'Closed case status should not be changed by a new comment');
    }

    @IsTest
    static void testResolvedCase_commentDoesNotChangeStatus() {
        Case c = makeCase('Resolved');

        Test.startTest();
        CaseComment cc = new CaseComment(
            ParentId    = c.Id,
            CommentBody = 'Comment on resolved case',
            IsPublished = true
        );
        insert cc;
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        Assert.areEqual('Resolved', updated.Status,
            'Resolved case status should not be changed by a new comment');
    }

    // ─── Bulk / batch handling ────────────────────────────────────────────────

    @IsTest
    static void testBulkComments_allCasesUpdated() {
        List<Case> cases = new List<Case>();
        Account a = new Account(Name = 'Bulk Account');
        insert a;
        for (Integer i = 0; i < 10; i++) {
            cases.add(new Case(
                Subject   = 'Bulk Case ' + i,
                Status    = 'New',
                AccountId = a.Id,
                Origin    = 'Web'
            ));
        }
        insert cases;

        List<CaseComment> comments = new List<CaseComment>();
        for (Case c : cases) {
            comments.add(new CaseComment(
                ParentId    = c.Id,
                CommentBody = 'Bulk comment',
                IsPublished = true
            ));
        }

        Test.startTest();
        insert comments;
        Test.stopTest();

        List<Case> updated = [SELECT Id, Status FROM Case WHERE Id IN :cases];
        for (Case c : updated) {
            Assert.areEqual('Waiting on Customer', c.Status,
                'All bulk cases should be updated to Waiting on Customer');
        }
    }

    @IsTest
    static void testBulkComments_mixedStatuses_onlyNonClosedUpdated() {
        Account a = new Account(Name = 'Mixed Bulk Account');
        insert a;

        Case openCase   = new Case(Subject = 'Open',   Status = 'New',    AccountId = a.Id, Origin = 'Web');
        Case closedCase = new Case(Subject = 'Closed', Status = 'Closed', AccountId = a.Id, Origin = 'Web');
        insert new List<Case>{ openCase, closedCase };

        List<CaseComment> comments = new List<CaseComment>{
            new CaseComment(ParentId = openCase.Id,   CommentBody = 'Open comment',   IsPublished = true),
            new CaseComment(ParentId = closedCase.Id, CommentBody = 'Closed comment', IsPublished = true)
        };

        Test.startTest();
        insert comments;
        Test.stopTest();

        Case openResult   = [SELECT Status FROM Case WHERE Id = :openCase.Id   LIMIT 1];
        Case closedResult = [SELECT Status FROM Case WHERE Id = :closedCase.Id LIMIT 1];

        Assert.areEqual('Waiting on Customer', openResult.Status,
            'Open case should be updated');
        Assert.areEqual('Closed', closedResult.Status,
            'Closed case should remain unchanged');
    }

    @IsTest
    static void testMultipleCommentsOnSameCase_noDuplicateUpdates() {
        Case c = makeCase('New');

        List<CaseComment> comments = new List<CaseComment>{
            new CaseComment(ParentId = c.Id, CommentBody = 'First',  IsPublished = true),
            new CaseComment(ParentId = c.Id, CommentBody = 'Second', IsPublished = true)
        };

        Test.startTest();
        insert comments; // Both in same DML → same trigger invocation
        Test.stopTest();

        // Verify no duplicate-update DML exception was thrown and status is correct
        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        Assert.areEqual('Waiting on Customer', updated.Status,
            'Status should be Waiting on Customer with no duplicate DML errors');
    }

    // ─── Null / edge cases ────────────────────────────────────────────────────

    @IsTest
    static void testAfterInsert_emptyList_doesNothing() {
        Test.startTest();
        // Call the handler directly with an empty list — should be a no-op
        CaseCommentTriggerHandler.afterInsert(new List<CaseComment>());
        Test.stopTest();
        // No exception = pass
    }

    @IsTest
    static void testAfterInsert_nullList_doesNothing() {
        Test.startTest();
        CaseCommentTriggerHandler.afterInsert(null);
        Test.stopTest();
        // No exception = pass
    }

    // ─── Trigger fires (integration smoke test) ───────────────────────────────

    @IsTest
    static void testTrigger_fires_onCaseCommentInsert() {
        // Validates the trigger itself is wired up to the handler
        Case c = makeCase('In Progress');

        Test.startTest();
        insertComment(c.Id, 'Trigger smoke test');
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :c.Id LIMIT 1];
        // Internal profile → agent → "Waiting on Customer"
        Assert.areEqual('Waiting on Customer', updated.Status,
            'Trigger should fire and delegate to handler correctly');
    }
}