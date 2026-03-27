// Hide the images, author, copyright
var classesToHide = ["qnwduuD2vJVpQe2nrnrX", "gnLigddXMHYKt5B0Jn9X", "px-2 pt-1"];
classesToHide.forEach( function(k, v) {
  var hideThese = document.getElementsByClassName(k);
  for (var i=0; i < hideThese.length; i++) {
    hideThese[i].style.opacity = 0;
  }
});
// Decrease border size
var resizeBorder = document.getElementsByClassName('hvRT8HCTTBtERQ62wnYf');
for(var i=0; i < resizeBorder.length; i++) {
  resizeBorder[i].style.borderWidth = "5px";
}
