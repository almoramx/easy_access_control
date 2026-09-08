module EasyAccessControl
  # View-side gate. `permitted` is the only way markup should depend on a
  # permission: it renders the block when the subject holds the key and, with
  # `config.debug_ui` on, boxes it with the key so testers see what unlocks it.
  module ViewHelper
    DEBUG_CSS = <<~CSS.freeze
      .eac-debug{position:relative;outline:1px dashed #007bff;outline-offset:2px;margin:2px}
      .eac-debug[data-eac-allowed="false"]{outline-color:#dc3545;min-height:1.5em}
      .eac-debug-tag{display:block;font:10px/1.4 ui-monospace,monospace;color:#fff;background:#007bff;padding:0 4px;width:max-content;max-width:100%;border-radius:2px}
      .eac-debug[data-eac-allowed="false"] .eac-debug-tag{background:#dc3545}
      .eac-debug-banner{font:12px/1.5 ui-monospace,monospace;background:#1f2937;color:#f9fafb;padding:4px 12px}
      .eac-debug-banner b{color:#93c5fd}
      .eac-debug-cell{position:relative;outline:1px dashed #007bff;outline-offset:-1px}
      .eac-debug-cell::after{content:attr(data-eac-key);position:absolute;top:0;right:0;font:9px/1.3 ui-monospace,monospace;color:#fff;background:#007bff;padding:0 3px;border-radius:0 0 0 2px;pointer-events:none}
      .eac-debug-cell[data-eac-allowed="false"]{outline-color:#dc3545;min-width:1.5em}
      .eac-debug-cell[data-eac-allowed="false"]::after{background:#dc3545}
    CSS

    # Without `as:` the block is wrapped in a block-level div — never put that
    # directly inside <table>/<tr> (browsers foster-parent it). With `as:` the
    # gate IS the element (`as: :th`, `as: :td`, extra attrs pass through): it
    # renders only when allowed and, in debug, carries the key as a corner
    # label + title tooltip instead of a wrapper; a denied cell shows up in
    # debug as an empty red cell so the missing key is visible.
    def permitted(key, scope: nil, as: nil, **attrs, &block)
      allowed = can?(key, scope: scope)
      label = [key, eac_scope_label(eac_scope_for(key, scope))].compact.join(" · ")
      label += " ✗" unless allowed
      if as
        return unless allowed || eac_debug?
        if eac_debug?
          attrs = attrs.merge(title: label, class: [attrs[:class], "eac-debug-cell"].compact.join(" "),
                              data: (attrs[:data] || {}).merge(eac_key: key, eac_allowed: allowed))
        end
        return content_tag(as, allowed && block ? capture(&block) : nil, **attrs)
      end
      content = allowed ? capture(&block) : nil
      return content unless eac_debug?
      tag.div(class: "eac-debug", title: label, data: { eac_key: key, eac_allowed: allowed }) do
        safe_join([tag.span(label, class: "eac-debug-tag"), content])
      end
    end

    # Styles + a banner with the keys authorize! demanded for this page.
    # Renders nothing when debug is off; drop it once in the layout.
    def eac_debug_toolbar
      return unless eac_debug?
      required = eac_required_permissions.map { |key, scope| [key, eac_scope_label(scope)].compact.join(" · ") }
      banner = tag.div(class: "eac-debug-banner") do
        safe_join([tag.b("authorize!"), " ", required.presence&.join(", ") || "none"])
      end
      safe_join([tag.style(DEBUG_CSS.html_safe), banner])
    end

    private

    def eac_scope_label(scope)
      return if scope.nil?
      scope.respond_to?(:name) ? scope.name : scope.to_param
    end
  end
end
