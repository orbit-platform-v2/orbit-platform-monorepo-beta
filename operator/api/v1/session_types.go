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

// SessionSpec defines the desired state of Session
type SessionSpec struct {
	// Challenge reference
	ChallengeName string `json:"challengeName"`

	// User information
	UserID   string `json:"userId"`
	UserName string `json:"userName,omitempty"`
	TeamID   string `json:"teamId,omitempty"`

	// Session configuration
	TTLSecondsAfterCreation *int32 `json:"ttlSecondsAfterCreation,omitempty"`

	// Resource overrides (if different from challenge defaults)
	Resources *ResourceRequirements `json:"resources,omitempty"`

	// Additional environment variables for this session
	Environment []EnvVar `json:"environment,omitempty"`

	// Session timeout in seconds (auto-cleanup on inactivity)
	// +kubebuilder:default=1800
	TimeoutSeconds *int32 `json:"timeoutSeconds,omitempty"`

	// Enable session recording
	RecordSession bool `json:"recordSession,omitempty"`
}

// SessionStatus defines the observed state of Session
type SessionStatus struct {
	// Phase of the session (Pending, Running, Succeeded, Failed, Terminating)
	// +kubebuilder:validation:Enum=Pending;Running;Succeeded;Failed;Terminating
	Phase string `json:"phase"`

	// Pod name created for this session
	PodName string `json:"podName,omitempty"`

	// Pod IP address
	PodIP string `json:"podIP,omitempty"`

	// WebSocket connection endpoint
	WebSocketEndpoint string `json:"webSocketEndpoint,omitempty"`

	// Session start time
	StartTime *metav1.Time `json:"startTime,omitempty"`

	// Session end time
	EndTime *metav1.Time `json:"endTime,omitempty"`

	// Last activity time (for timeout tracking)
	LastActivityTime *metav1.Time `json:"lastActivityTime,omitempty"`

	// Resource usage statistics
	ResourceUsage *ResourceUsage `json:"resourceUsage,omitempty"`

	// Conditions represent the latest available observations
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// Reason for current status
	Reason string `json:"reason,omitempty"`

	// Human-readable message
	Message string `json:"message,omitempty"`
}

// ResourceUsage represents resource consumption statistics
type ResourceUsage struct {
	// CPU usage in millicores
	CPUUsage string `json:"cpuUsage,omitempty"`

	// Memory usage in bytes
	MemoryUsage string `json:"memoryUsage,omitempty"`

	// Storage usage in bytes
	StorageUsage string `json:"storageUsage,omitempty"`

	// Network bytes received
	NetworkRX string `json:"networkRX,omitempty"`

	// Network bytes transmitted
	NetworkTX string `json:"networkTX,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:printcolumn:name="Challenge",type="string",JSONPath=".spec.challengeName"
//+kubebuilder:printcolumn:name="User",type="string",JSONPath=".spec.userId"
//+kubebuilder:printcolumn:name="Phase",type="string",JSONPath=".status.phase"
//+kubebuilder:printcolumn:name="Pod",type="string",JSONPath=".status.podName"
//+kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
//+kubebuilder:printcolumn:name="Last Activity",type="date",JSONPath=".status.lastActivityTime"

// Session is the Schema for the sessions API
type Session struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   SessionSpec   `json:"spec,omitempty"`
	Status SessionStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// SessionList contains a list of Session
type SessionList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Session `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Session{}, &SessionList{})
}
