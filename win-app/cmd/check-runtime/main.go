// Verify a participant package without starting an exam.
package main
import("fmt";"os";"roundlane/windows/core")
func main(){if len(os.Args)!=2{fmt.Fprintln(os.Stderr,"usage: check-runtime PACKAGE_DIRECTORY");os.Exit(2)};if err:=core.VerifyRuntime(os.Args[1]);err!=nil{fmt.Fprintln(os.Stderr,err);os.Exit(1)};fmt.Println(`{"passed":true,"exam_started":false}`)}
