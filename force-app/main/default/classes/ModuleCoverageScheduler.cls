/**
 * Schedulable entry point for the nightly Module Coverage refresh.
 * Schedule once, e.g. from anonymous Apex:
 *   System.schedule('Module Coverage Nightly', '0 0 2 * * ?', new ModuleCoverageScheduler());
 */
public with sharing class ModuleCoverageScheduler implements Schedulable {

	private static final Integer BATCH_SIZE = 200;

	public void execute(SchedulableContext sc) {
		Database.executeBatch(new ModuleCoverageBatch(), BATCH_SIZE);
	}
}
