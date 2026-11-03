trigger ContentVersionTrigger on ContentVersion(before insert, after insert) {
	new ContentVersionTriggerHandler().run();
}
