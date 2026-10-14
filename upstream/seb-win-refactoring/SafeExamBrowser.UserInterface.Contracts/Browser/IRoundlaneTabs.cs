// Roundlane additions, MPL-2.0.
using System;
using System.Collections.Generic;
namespace SafeExamBrowser.UserInterface.Contracts.Browser
{
    public sealed class RoundlaneBrowserTab
    {
        public int Id { get; set; }
        public string Title { get; set; }
        public bool Selected { get; set; }
        public bool CanClose { get; set; }
    }
    public interface IRoundlaneTabs
    {
        event Action<int> TabSelected;
        event Action<int> TabClosed;
        event Action<string> TabCommand;
        event Action TabActivated;
        void UpdateTabs(IEnumerable<RoundlaneBrowserTab> tabs);
    }
}
