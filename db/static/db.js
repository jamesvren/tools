function switchSSH(x) {
	var ssh_class = document.getElementById(x).checked?"ssh_checked":"ssh_info";
	document.getElementById("ssh_info").className = ssh_class;
}

var toggler = document.getElementsByClassName("caret");
var i;

for (i = 0; i < toggler.length; i++) {
  toggler[i].addEventListener("click", function() {
    this.parentElement.querySelector(".nested").classList.toggle("active");
    this.classList.toggle("caret-down");
  });
}
