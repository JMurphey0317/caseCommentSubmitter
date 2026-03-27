/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CaseCommentTriggerHandler
 * Author          : SaltClick
 * Created Date    : Mar 27, 2026
 * Last Modified By: SaltClick
 * Last Modified On: Mar 27, 2026
 * Description     : Handles Case Status updates from Comments made not in the LWC
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 27, 2026  │ SaltClick   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public with sharing class CaseCommentTriggerHandler {

    public static void afterInsert(List<CaseComment> newComments) {
        if (newComments == null || newComments.isEmpty()) return;

        Set<Id> caseIds = new Set<Id>();
        Set<Id> creatorUserIds = new Set<Id>();
        for (CaseComment cc : newComments) {
            if (cc == null || cc.ParentId == null) continue;
            caseIds.add(cc.ParentId);
            if (cc.CreatedById != null) creatorUserIds.add(cc.CreatedById);
        }
        if (caseIds.isEmpty()) return;

        Map<Id, Case> casesById = new Map<Id, Case>([
            SELECT Id, Status
            FROM Case
            WHERE Id IN :caseIds
        ]);

        Map<Id, User> usersById = new Map<Id, User>();
        if (!creatorUserIds.isEmpty()) {
            usersById = new Map<Id, User>([
                SELECT Id, Profile.Name
                FROM User
                WHERE Id IN :creatorUserIds
            ]);
        }

        List<Case> casesToUpdate = new List<Case>();

        for (CaseComment cc : newComments) {
            Case parentCase = casesById.get(cc.ParentId);
            if (parentCase == null) continue;

            // Allow comments, but never change status when closed/resolved
            String st = (parentCase.Status == null) ? '' : parentCase.Status.trim().toLowerCase();
            if (st == 'closed' || st == 'resolved') {
                continue;
            }

            User creator = usersById.get(cc.CreatedById);
            String profileName = (creator != null && creator.Profile != null) ? creator.Profile.Name : null;

            Boolean isAgent = deriveIsAgent(profileName);
            String desiredStatus = isAgent ? 'Waiting on Customer' : 'In Progress';

            if (parentCase.Status != desiredStatus) {
                casesToUpdate.add(new Case(Id = parentCase.Id, Status = desiredStatus));
                parentCase.Status = desiredStatus; // prevents duplicates in same batch
            }
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
    }

    private static Boolean deriveIsAgent(String profileName) {
        String pn = (profileName == null) ? '' : profileName.toLowerCase();
        return !(pn.contains('community') || pn.contains('portal'));
    }
}