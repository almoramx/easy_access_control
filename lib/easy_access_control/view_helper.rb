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
    CSS

    # Wrapping in a block-level div: don't wrap <tr>/<td>/<th> (tables would
    # foster-parent it); keep a `can?` boolean for column visibility.
    def permitted(key, scope: nil, &block)
      allowed = can?(key, scope: scope)
      content = allowed ? capture(&block) : nil
      return content unless eac_debug?
      label = [key, eac_scope_label(scope)].compact.join(" · ")
      label += " ✗" unless allowed
      tag.div(class: "eac-debug", data: { eac_key: key, eac_allowed: allowed }) do
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
