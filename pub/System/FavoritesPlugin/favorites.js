(function($) {
  $(document).ready( function() {
    var p = foswiki.preferences;
    var viewUrl = [
      p.SCRIPTURLPATH,
      '/view',
      p.SCRIPTSUFFIX
    ].join('');

    $('.foswikiPage').on('submit', 'form[action*="FavoritesPlugin/update"]', function() {
      var $form = $(this);
      var target = $form.attr('action');
      var method = $form.attr('method');

      var payload = {};
      $form.children('input[type="hidden"]').each(function() {
        var $in = $(this);
        payload[$in.attr('name')] = $in.attr('value');
      });

      if (payload.validation_key) {
        payload.validation_key = payload.validation_key.replace(/\?/g, '');
      }

      var redirect = payload.redirect;
      delete payload.redirect;

      $.blockUI();
      $.ajax({
        method: method,
        url: target,
        data: payload
      }).error($.unblockUI).done(function() {
        var $div = $('<div />');
        $div.load(viewUrl + '/' + redirect + ' form[action*="FavoritesPlugin/update"]', function(a,b,c) {
          var $in = $div.find('input[name="file"][value="' + payload.file + '"]');
          $form.replaceWith($in.parent());
          $.unblockUI();
        })
      });

      return false;
    })
  });
})(jQuery);
