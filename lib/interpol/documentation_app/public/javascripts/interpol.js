$(document).ready(function() {
  $(".nav-list a").click(function() {
    var endpointName = $(this).attr("data-endpoint-name");
    $('.endpoint-documentation-wrapper').hide();
    $('#' + endpointName + '.endpoint-documentation-wrapper').show();
    $('ul.nav-list li').removeClass("active");
    $(this).parents("ul.nav-list li").addClass("active");
  });
});

