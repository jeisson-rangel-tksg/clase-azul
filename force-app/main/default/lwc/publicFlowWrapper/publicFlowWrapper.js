import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class PublicFlowWrapper extends LightningElement {
  @track inputVariables = [];

  @wire(CurrentPageReference)
  setParams(ref) {
    if (!ref) return;
    const params = ref.state || {};
    const surveyId = params.surveyId; // e.g., ?surveyId=0K3xxxxxx

    this.inputVariables = [
      { name: 'surveyId', type: 'String', value: surveyId }
    ];
  }

  handleStatusChange(event) {
    if (event.detail.status === 'FINISHED') {
      const outs = event.detail.outputVariables || [];
      const linkVar = outs.find(v => v.name === 'redirectUrl');
      if (linkVar && linkVar.value) {
        window.location.href = linkVar.value; // redirect to SurveyInvitation.InvitationLink
      }
    }
  }
}
