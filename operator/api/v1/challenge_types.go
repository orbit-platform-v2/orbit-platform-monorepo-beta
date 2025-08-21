/*
Copyright 2024 Orbit Challenge Platform.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// ChallengeSpec defines the desired state of Challenge
type ChallengeSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Name of the challenge
	Name string `json:"name"`

	// Description of the challenge
	Description string `json:"description"`

	// Docker image for the challenge container
	Image string `json:"image"`

	// ImagePullPolicy defines when to pull the image
	// +kubebuilder:default="IfNotPresent"
	ImagePullPolicy string `json:"imagePullPolicy,omitempty"`

	// Resource requirements for challenge pods
	Resources ResourceRequirements `json:"resources,omitempty"`

	// TTL (Time To Live) for challenge sessions in seconds
	// +kubebuilder:default=1800
	TTLSecondsAfterCreation *int32 `json:"ttlSecondsAfterCreation,omitempty"`

	// Maximum number of concurrent sessions for this challenge
	// +kubebuilder:default=10
	MaxSessions int32 `json:"maxSessions,omitempty"`

	// Environment variables to inject into challenge pods
	Environment []EnvVar `json:"environment,omitempty"`

	// Files to mount into the challenge container
	Files []FileMount `json:"files,omitempty"`

	// Ports to expose from the challenge container
	Ports []Port `json:"ports,omitempty"`

	// Instructions for the challenge
	Instructions string `json:"instructions,omitempty"`

	// Hints for the challenge
	Hints []string `json:"hints,omitempty"`

	// Difficulty level (beginner, intermediate, advanced)
	// +kubebuilder:validation:Enum=beginner;intermediate;advanced
	Difficulty string `json:"difficulty,omitempty"`

	// Tags for categorizing challenges
	Tags []string `json:"tags,omitempty"`

	// Required capabilities for the challenge pod
	Capabilities []string `json:"capabilities,omitempty"`

	// Network policies to apply
	NetworkPolicy *NetworkPolicySpec `json:"networkPolicy,omitempty"`
}

// ResourceRequirements defines resource requirements for challenge pods
type ResourceRequirements struct {
	// CPU limit (e.g., "500m")
	// +kubebuilder:default="500m"
	CPU string `json:"cpu,omitempty"`

	// Memory limit (e.g., "1Gi")
	// +kubebuilder:default="1Gi"
	Memory string `json:"memory,omitempty"`

	// Storage limit (e.g., "5Gi")
	// +kubebuilder:default="5Gi"
	Storage string `json:"storage,omitempty"`
}

// EnvVar represents an environment variable
type EnvVar struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// FileMount represents a file to mount in the container
type FileMount struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	Content   string `json:"content,omitempty"`
	ConfigMap string `json:"configMap,omitempty"`
	Secret    string `json:"secret,omitempty"`
}

// Port represents a port to expose
type Port struct {
	Name          string `json:"name"`
	ContainerPort int32  `json:"containerPort"`
	Protocol      string `json:"protocol,omitempty"`
}

// NetworkPolicySpec defines network policy configuration
type NetworkPolicySpec struct {
	// Allow ingress traffic
	AllowIngress []NetworkPolicyIngressRule `json:"allowIngress,omitempty"`

	// Allow egress traffic
	AllowEgress []NetworkPolicyEgressRule `json:"allowEgress,omitempty"`

	// Default deny all traffic
	DenyAll bool `json:"denyAll,omitempty"`
}

// NetworkPolicyIngressRule defines ingress rules
type NetworkPolicyIngressRule struct {
	From  []NetworkPolicyPeer `json:"from,omitempty"`
	Ports []NetworkPolicyPort `json:"ports,omitempty"`
}

// NetworkPolicyEgressRule defines egress rules
type NetworkPolicyEgressRule struct {
	To    []NetworkPolicyPeer `json:"to,omitempty"`
	Ports []NetworkPolicyPort `json:"ports,omitempty"`
}

// NetworkPolicyPeer defines allowed peers
type NetworkPolicyPeer struct {
	PodSelector       *metav1.LabelSelector `json:"podSelector,omitempty"`
	NamespaceSelector *metav1.LabelSelector `json:"namespaceSelector,omitempty"`
	IPBlock           *IPBlock              `json:"ipBlock,omitempty"`
}

// NetworkPolicyPort defines allowed ports
type NetworkPolicyPort struct {
	Protocol string `json:"protocol,omitempty"`
	Port     string `json:"port,omitempty"`
}

// IPBlock defines an IP block
type IPBlock struct {
	CIDR   string   `json:"cidr"`
	Except []string `json:"except,omitempty"`
}

// ChallengeStatus defines the observed state of Challenge
type ChallengeStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Number of active sessions
	ActiveSessions int32 `json:"activeSessions"`

	// Total number of sessions created
	TotalSessions int32 `json:"totalSessions"`

	// Last session creation time
	LastSessionTime *metav1.Time `json:"lastSessionTime,omitempty"`

	// Challenge availability status
	Available bool `json:"available"`

	// Reason for current status
	Reason string `json:"reason,omitempty"`

	// Conditions represent the latest available observations
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:subresource:scale:specpath=.spec.maxSessions,statuspath=.status.activeSessions
//+kubebuilder:printcolumn:name="Image",type="string",JSONPath=".spec.image"
//+kubebuilder:printcolumn:name="Difficulty",type="string",JSONPath=".spec.difficulty"
//+kubebuilder:printcolumn:name="Active",type="integer",JSONPath=".status.activeSessions"
//+kubebuilder:printcolumn:name="Max",type="integer",JSONPath=".spec.maxSessions"
//+kubebuilder:printcolumn:name="Available",type="boolean",JSONPath=".status.available"
//+kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// Challenge is the Schema for the challenges API
type Challenge struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ChallengeSpec   `json:"spec,omitempty"`
	Status ChallengeStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// ChallengeList contains a list of Challenge
type ChallengeList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Challenge `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Challenge{}, &ChallengeList{})
}
