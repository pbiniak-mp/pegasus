trigger DesignRevisionTrigger on Design_Revision__c(before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	new DesignRevisionTriggerHandler().run();
}
