package main

import (
	"encoding/json"
	"testing"

	LC "github.com/metacubex/mihomo/listener/config"
)

func TestPatchTunMsgX(t *testing.T) {
	target := LC.Tun{RecvMsgX: true}
	var params tunSchema
	if err := json.Unmarshal([]byte(`{"recvmsgx":false,"sendmsgx":true}`), &params); err != nil {
		t.Fatal(err)
	}
	patchTun(&target, &params)
	if target.RecvMsgX || !target.SendMsgX {
		t.Fatalf("explicit switches were not applied: %+v", target)
	}
	patchTun(&target, &tunSchema{})
	if target.RecvMsgX || !target.SendMsgX {
		t.Fatal("omitted switches changed existing values")
	}
}
