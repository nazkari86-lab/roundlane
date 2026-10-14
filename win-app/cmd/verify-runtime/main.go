// Offline, cross-platform check of a Roundlane Windows installation directory.
package main

import (
	"fmt"
	"os"
	"roundlane/windows/core"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: verify-runtime INSTALL_DIRECTORY")
		os.Exit(2)
	}
	if err := core.VerifyRuntime(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Roundlane manifest signature and all runtime files verified")
}
