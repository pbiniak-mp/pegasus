/**
 * Schedulable entry point for the nightly log clean-up. Schedule once, from anonymous Apex:
 *   System.schedule('Log Retention Nightly', '0 0 0 * * ?', new LogRetentionScheduler());
 *
 * Everything about what gets purged lives in Log_Retention_Policy__mdt, so retention
 * windows change (and objects are added or paused) without touching this code.
 */
public without sharing class LogRetentionScheduler implements Schedulable {

	public void execute(SchedulableContext context) {
		LogRetentionBatch.run(LogRetentionPolicySelector.getActivePolicies());
	}
}
