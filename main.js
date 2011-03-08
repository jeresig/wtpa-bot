$(function(){
	$("#upcoming form.update").hide().bind("reset", function() {
		$(this).hide();
		return false;
	});
	
	$("#upcoming input.update").click(function() {
		$(this).parents("li").find("form.update").toggle();
	});
	
	$("#upcoming form.cancel").submit(function() {
		return confirm( "Are you sure you wish to cancel this event?" );
	});
});