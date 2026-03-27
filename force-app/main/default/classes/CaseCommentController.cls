/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CaseCommentController
 * Author          : SaltClick
 * Created Date    : Mar 23, 2026
 * Last Modified By: SaltClick
 * Last Modified On: Mar 25, 2026
 * Description     : Apex controller for the caseCommentSubmitter LWC.
 *                   Supports Experience Cloud (community) and internal record pages.
 *
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public without sharing class CaseCommentController {

    // ─── Query Methods ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CommentWrapper> getCaseComments(Id caseId) {
        if (caseId == null) return new List<CommentWrapper>();
        assertCaseAccess(caseId);

        List<CaseComment> comments = [
            SELECT Id, CommentBody, CreatedDate,
                   CreatedBy.Name, CreatedBy.Profile.Name,
                   IsPublished
            FROM   CaseComment
            WHERE  ParentId    = :caseId
            AND    IsPublished = true
            ORDER BY CreatedDate ASC
            LIMIT  500
        ];

        if (comments.isEmpty()) return new List<CommentWrapper>();

        Set<Id> commentIds = new Map<Id, CaseComment>(comments).keySet();

        // ── Source 1: Files linked via Case_Comment_File__c junction object
        // Covers community user uploads via LWC and any programmatic links
        List<String> commentIdStrings = new List<String>();
        for (Id i : commentIds) commentIdStrings.add(String.valueOf(i));

        List<Case_Comment_File__c> mappings = [
            SELECT CaseCommentId__c, ContentDocumentId__c
            FROM   Case_Comment_File__c
            WHERE  Case__c           = :caseId
            AND    CaseCommentId__c IN :commentIdStrings
        ];

        Set<Id> junctionDocIds = new Set<Id>();
        Map<String, List<String>> junctionDocsByComment = new Map<String, List<String>>();
        for (Case_Comment_File__c m : mappings) {
            if (String.isBlank(m.CaseCommentId__c) || String.isBlank(m.ContentDocumentId__c)) continue;
            if (!junctionDocsByComment.containsKey(m.CaseCommentId__c)) {
                junctionDocsByComment.put(m.CaseCommentId__c, new List<String>());
            }
            junctionDocsByComment.get(m.CaseCommentId__c).add(m.ContentDocumentId__c);
            try { junctionDocIds.add((Id) m.ContentDocumentId__c); } catch (Exception e) {}
        }

        // ── Source 2: Files attached natively to the Case by SF agents via UI
        // Query Case-level CDLs and match to nearest comment by CreatedDate
        List<ContentDocumentLink> caseCdls = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.CreatedDate
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId    = :caseId
            AND    ContentDocumentId NOT IN :junctionDocIds
        ];

        // Map agent-uploaded docs to nearest comment within 5 minutes
        Map<String, List<String>> agentDocsByComment = new Map<String, List<String>>();
        Set<Id> agentDocIds = new Set<Id>();

        if (!caseCdls.isEmpty() && !comments.isEmpty()) {
            for (ContentDocumentLink cdl : caseCdls) {
                if (cdl.ContentDocument == null) continue;
                CaseComment nearest = comments[0];
                Long minDiff = Math.abs(
                    nearest.CreatedDate.getTime()
                    - cdl.ContentDocument.CreatedDate.getTime()
                );
                for (CaseComment cc : comments) {
                    Long diff = Math.abs(
                        cc.CreatedDate.getTime()
                        - cdl.ContentDocument.CreatedDate.getTime()
                    );
                    if (diff < minDiff) {
                        minDiff = diff;
                        nearest = cc;
                    }
                }
                if (minDiff <= 300000) {
                    String commentIdStr = String.valueOf(nearest.Id);
                    if (!agentDocsByComment.containsKey(commentIdStr)) {
                        agentDocsByComment.put(commentIdStr, new List<String>());
                    }
                    agentDocsByComment.get(commentIdStr).add(
                        String.valueOf(cdl.ContentDocumentId)
                    );
                    agentDocIds.add(cdl.ContentDocumentId);
                }
            }
        }

        // ── Fetch all ContentDocument metadata in one query
        Set<Id> allDocIds = new Set<Id>();
        allDocIds.addAll(junctionDocIds);
        allDocIds.addAll(agentDocIds);

        Map<Id, ContentDocument> docsById = new Map<Id, ContentDocument>();
        if (!allDocIds.isEmpty()) {
            docsById = new Map<Id, ContentDocument>([
                SELECT Id, Title, FileExtension
                FROM   ContentDocument
                WHERE  Id IN :allDocIds
            ]);
        }

        // ── Build output
        List<CommentWrapper> out = new List<CommentWrapper>();
        for (CaseComment cc : comments) {
            CommentWrapper w  = toWrapper(cc);
            List<FileWrapper> files = new List<FileWrapper>();
            Set<Id> seenDocIds = new Set<Id>();

            String idStr = String.valueOf(cc.Id);

            // Add junction object files
            if (junctionDocsByComment.containsKey(idStr)) {
                for (String docIdStr : junctionDocsByComment.get(idStr)) {
                    Id docId;
                    try { docId = (Id) docIdStr; } catch (Exception e) { continue; }
                    if (seenDocIds.contains(docId)) continue;
                    ContentDocument doc = docsById.get(docId);
                    if (doc == null) continue;
                    files.add(buildFileWrapper(doc));
                    seenDocIds.add(docId);
                }
            }

            // Add agent-uploaded files matched by timestamp
            if (agentDocsByComment.containsKey(idStr)) {
                for (String docIdStr : agentDocsByComment.get(idStr)) {
                    Id docId;
                    try { docId = (Id) docIdStr; } catch (Exception e) { continue; }
                    if (seenDocIds.contains(docId)) continue;
                    ContentDocument doc = docsById.get(docId);
                    if (doc == null) continue;
                    files.add(buildFileWrapper(doc));
                    seenDocIds.add(docId);
                }
            }

            w.files = files;
            out.add(w);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static CaseInfoWrapper getCaseInfo(Id caseId) {
        if (caseId == null) return null;
        assertCaseAccess(caseId);

        Case c = [SELECT CaseNumber, Subject, Status FROM Case WHERE Id = :caseId LIMIT 1];
        CaseInfoWrapper w = new CaseInfoWrapper();
        w.caseNumber = c.CaseNumber;
        w.subject    = c.Subject;
        w.status     = c.Status;
        return w;
    }

    // ─── Mutation Method ─────────────────────────────────────────────────────

    @AuraEnabled
    public static CommentWrapper addCaseComment(
        Id          caseId,
        String      commentBody,
        List<Id>    contentDocumentIds
    ) {
        if (caseId == null)              throw new AuraHandledException('Case Id is required.');
        if (String.isBlank(commentBody)) throw new AuraHandledException('Comment cannot be blank.');

        String trimmed = commentBody.trim();
        if (trimmed.length() > 4000) throw new AuraHandledException('Comment exceeds 4,000 characters.');
        assertCaseAccess(caseId);

        // Prevent comments on closed/resolved cases (status updates handled by CaseComment trigger)
        Case c = [SELECT Id, Status FROM Case WHERE Id = :caseId LIMIT 1];
        String st = (c.Status == null) ? '' : c.Status.trim().toLowerCase();
        if (st == 'closed' || st == 'resolved') {
            throw new AuraHandledException('This case is closed and cannot receive new comments.');
        }

        CaseComment cc = new CaseComment(
            ParentId    = caseId,
            CommentBody = trimmed,
            IsPublished = true
        );
        insert cc;

        List<FileWrapper> returnFiles = new List<FileWrapper>();

        if (contentDocumentIds != null && !contentDocumentIds.isEmpty()) {

            Set<Id> passedIds = new Set<Id>();
            for (Id rawId : contentDocumentIds) {
                if (rawId != null) passedIds.add(rawId);
            }

            Map<Id, Id> versionToDoc = new Map<Id, Id>();
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId
                FROM   ContentVersion
                WHERE  Id IN :passedIds
            ]) {
                versionToDoc.put(cv.Id, cv.ContentDocumentId);
            }

            Set<Id> resolvedDocIds = new Set<Id>();
            for (Id rawId : passedIds) {
                if (versionToDoc.containsKey(rawId)) {
                    resolvedDocIds.add(versionToDoc.get(rawId));
                } else {
                    resolvedDocIds.add(rawId);
                }
            }

            if (!resolvedDocIds.isEmpty()) {

                // Insert Case_Comment_File__c junction records
                List<Case_Comment_File__c> links = new List<Case_Comment_File__c>();
                for (Id docId : resolvedDocIds) {
                    links.add(new Case_Comment_File__c(
                        Case__c              = caseId,
                        CaseCommentId__c     = String.valueOf(cc.Id),
                        ContentDocumentId__c = String.valueOf(docId)
                    ));
                }
                insert links;

                List<ContentDocumentLink> caseLinks = [
                    SELECT Id, Visibility
                    FROM   ContentDocumentLink
                    WHERE  LinkedEntityId    = :caseId
                    AND    ContentDocumentId IN :resolvedDocIds
                    AND    Visibility        != 'AllUsers'
                ];
                if (!caseLinks.isEmpty()) {
                    for (ContentDocumentLink cdl : caseLinks) cdl.Visibility = 'AllUsers';
                    update caseLinks;
                }

                // Build return file list
                for (ContentDocument doc : [
                    SELECT Id, Title, FileExtension
                    FROM   ContentDocument
                    WHERE  Id IN :resolvedDocIds
                ]) {
                    returnFiles.add(buildFileWrapper(doc));
                }
            }
        }

        cc = [
            SELECT Id, CommentBody, CreatedDate,
                   CreatedBy.Name, CreatedBy.Profile.Name,
                   IsPublished
            FROM   CaseComment
            WHERE  Id = :cc.Id
            LIMIT  1
        ];

        CommentWrapper w = toWrapper(cc);
        w.files = returnFiles;
        return w;
    }

    // ─── Visibility Repair ───────────────────────────────────────────────────

    @AuraEnabled
    public static void fixFileVisibilityForCase(Id caseId) {
        if (caseId == null) return;
        assertCaseAccess(caseId);

        List<ContentDocumentLink> caseLinks = [
            SELECT Id, Visibility
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :caseId
            AND    Visibility    != 'AllUsers'
        ];
        if (!caseLinks.isEmpty()) {
            for (ContentDocumentLink cdl : caseLinks) cdl.Visibility = 'AllUsers';
            update caseLinks;
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────���──

    private static void assertCaseAccess(Id caseId) {
        List<Case> rows = [SELECT Id FROM Case WHERE Id = :caseId LIMIT 1];
        if (rows.isEmpty()) {
            throw new AuraHandledException('You do not have permission to access this case.');
        }
    }

    private static Boolean deriveIsAgent(String profileName) {
        String pn = (profileName == null) ? '' : profileName.toLowerCase();
        return !(pn.contains('community') || pn.contains('portal'));
    }

    private static CommentWrapper toWrapper(CaseComment cc) {
        CommentWrapper w = new CommentWrapper();
        w.id             = cc.Id;
        w.body           = cc.CommentBody;
        w.createdDate    = cc.CreatedDate;
        w.authorName     = (cc.CreatedBy != null && String.isNotBlank(cc.CreatedBy.Name))
                               ? cc.CreatedBy.Name : 'Support Agent';
        w.isPublished    = cc.IsPublished;
        w.isAgent        = deriveIsAgent(
                               cc.CreatedBy != null && cc.CreatedBy.Profile != null
                                   ? cc.CreatedBy.Profile.Name : null
                           );
        w.files          = new List<FileWrapper>();
        return w;
    }

    private static FileWrapper buildFileWrapper(ContentDocument doc) {
        FileWrapper fw       = new FileWrapper();
        fw.contentDocumentId = doc.Id;
        fw.title             = doc.Title;
        fw.fileExtension     = doc.FileExtension != null
                                   ? doc.FileExtension.toUpperCase() : '';
        fw.downloadUrl       = '/sfc/servlet.shepherd/document/download/' + doc.Id;
        return fw;
    }

    // ─── Wrapper Classes ──────────────────────────────────────────────────────

    public class CommentWrapper {
        @AuraEnabled public Id                id;
        @AuraEnabled public String            body;
        @AuraEnabled public DateTime          createdDate;
        @AuraEnabled public String            authorName;
        @AuraEnabled public Boolean           isPublished;
        @AuraEnabled public Boolean           isAgent;
        @AuraEnabled public List<FileWrapper> files;
    }

    public class CaseInfoWrapper {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
    }

    public class FileWrapper {
        @AuraEnabled public Id     contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String downloadUrl;
    }
}