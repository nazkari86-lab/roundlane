/*
 * Copyright (c) 2025 ETH Zürich, IT Services
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using SafeExamBrowser.Configuration.Contracts;
using SafeExamBrowser.Configuration.Integrity;

namespace SafeExamBrowser.Runtime
{
	public class App : Application
	{
		private static readonly Mutex Mutex = new Mutex(true, AppConfig.RUNTIME_MUTEX_NAME);
		private readonly CompositionRoot instances = new CompositionRoot();

		[STAThread]
		public static void Main()
		{
			var arguments = Environment.GetCommandLineArgs();
            if (arguments.Length == 3 && arguments[1] == "--roundlane-integrity-check")
            {
                var guard = RoundlaneGuard.Current;
                var releaseValid = guard.VerifyRelease(out var releaseReason);
                var memoryValid = guard.VerifyMemory(out var memoryReason);
                var valid = releaseValid && memoryValid;
                File.WriteAllText(arguments[2], valid ? "passed" : "failed");
                if (!valid)
                {
                    File.WriteAllText(arguments[2] + ".error.txt", releaseReason ?? memoryReason ?? "integrity failed");
                    Environment.ExitCode = 1;
                }
                Mutex.Close();
                return;
            }
			if (arguments.Length == 3 && arguments[1] == "--roundlane-runtime-check")
			{
				try
				{
					var application = new App();
					application.instances.BuildObjectGraph(() => { });
					File.WriteAllText(arguments[2], "{\"runtime_object_graph\":\"passed\",\"exam_started\":false}");
				}
				catch (Exception error)
				{
					File.WriteAllText(arguments[2], "{\"runtime_object_graph\":\"failed\",\"exam_started\":false}");
					File.WriteAllText(arguments[2] + ".error.txt", error.ToString());
					Environment.ExitCode = 1;
				}
				finally { Mutex.Close(); }
				return;
			}
			try
			{
				StartApplication();
			}
			catch (Exception e)
			{
				MessageBox.Show(e.Message + "\n\n" + e.StackTrace, "Fatal Error", MessageBoxButton.OK, MessageBoxImage.Error);
			}
			finally
			{
				Mutex.Close();
			}
		}

		private static void StartApplication()
		{
			if (NoInstanceRunning())
			{
				RoundlaneGuard.InitializeRuntimeSignal();
                new App().Run();
			}
			else
			{
				MessageBox.Show("You can only run one instance of Roundlane at a time.", "Startup Not Allowed", MessageBoxButton.OK, MessageBoxImage.Information);
			}
		}

		private static bool NoInstanceRunning()
		{
			return Mutex.WaitOne(TimeSpan.Zero, true);
		}

		protected override void OnStartup(StartupEventArgs e)
		{
			base.OnStartup(e);

			ShutdownMode = ShutdownMode.OnExplicitShutdown;

			instances.BuildObjectGraph(Shutdown);
			instances.LogStartupInformation();

			Task.Run(new Action(TryStart));
		}

		private void TryStart()
		{
			var success = instances.RuntimeController.TryStart();
			var readyFile = Environment.GetEnvironmentVariable("ROUNDLANE_READY_FILE");
			if (success && !string.IsNullOrWhiteSpace(readyFile))
			{
				try { File.WriteAllText(readyFile, "session-ready"); }
				catch { Shutdown(); return; }
			}

			if (!success)
			{
				Shutdown();
			}
		}

		public new void Shutdown()
		{
			Task.Run(new Action(ShutdownInternal));
		}

		private void ShutdownInternal()
		{
			instances.RuntimeController.Terminate();
			instances.LogShutdownInformation();

			Dispatcher.Invoke(base.Shutdown);
		}
	}
}
