/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/inventory.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

function openInvTab(evt, tabName) {
  let i, x, tablinks;

  // Hide all tabs
  x = document.getElementsByClassName("inv-tab");
  for (i = 0; i < x.length; i++) {
    x[i].style.display = "none";
  }

  // Remove active highlight from all buttons
  tablinks = document.getElementsByClassName("tablink");
  for (i = 0; i < tablinks.length; i++) {
    tablinks[i].className = tablinks[i].className.replace(" w3-blue", "");
  }

  // Show the targeted tab and highlight the clicked button
  document.getElementById(tabName).style.display = "block";
  evt.currentTarget.className += " w3-blue";
}
