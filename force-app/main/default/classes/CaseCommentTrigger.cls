/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 03-27-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger CaseCommentTrigger on CaseComment (after insert) {
    CaseCommentTriggerHandler.afterInsert(Trigger.new);
}