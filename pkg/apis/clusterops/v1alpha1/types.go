package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +genclient
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
// +k8s:resource:shortName=labeler,scope=Namespaced,shortName=lbl,categoies=all
// +genreconciler:krshapedlogic=false

type Labeler struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec LabelerSpec `json:"spec"`
}

type LabelerSpec struct {
	CustomLabels map[string]string `json:"customLabels"`
}

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
type LabelerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Labeler `json:"items"`
}
