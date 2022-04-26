// This LINQPad script helps you to delete TFVC workspaces older than X using TFS TFVC API
// Attention: You need to add the package https://www.nuget.org/packages/Microsoft.TeamFoundationServer.ExtendedClient in LinqPad !!!

void Main()
{
	var tfs = TfsTeamProjectCollectionFactory
				.GetTeamProjectCollection(new Uri("https://<tfsurl>/tfs/DefaultCollection"));
	tfs.EnsureAuthenticated();


	var tfvc = tfs.GetService<VersionControlServer>();
  
  // Get workspace data
	var workspacesOld = tfvc.QueryWorkspaces(null, null, null).Where(x => x.LastAccessDate <= DateTime.Parse("09.02.2020"));
	var workspacesNew = tfvc.QueryWorkspaces(null, null, null).Where(x => x.LastAccessDate > DateTime.Parse("09.02.2020"));

  // Show some statistics
	tfs.Uri.Dump("Server url");

	workspacesOld.Count().Dump("Older than 2 years");
	workspacesNew.Count().Dump("Newer than 2 years");
	//workspacesOld.Dump();

	workspacesOld.OrderBy(X => X.LastAccessDate).First().LastAccessDate.Dump("Oldest workspace access date");
	workspacesOld.OrderBy(X => X.LastAccessDate).Last().LastAccessDate.Dump("Lastest workspace access date");

  // do the actual work
	foreach (var workspace in workspacesOld.OrderBy(X => X.LastAccessDate))
	{
		workspace.Name.Dump();
		workspace.LastAccessDate.Dump();
		workspace.Delete();
	}
}
