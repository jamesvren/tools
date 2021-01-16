function switchSSH(x) {
	var ssh_class = document.getElementById(x).checked?"ssh_checked":"ssh_info";
	document.getElementById("ssh_info").className = ssh_class;
}