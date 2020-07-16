module RedmineWebhook
  class WebhookListener < Redmine::Hook::Listener

    def skip_webhooks(context)
      return true unless context[:request]
      return true if context[:request].headers['X-Skip-Webhooks']

      false
    end

    def controller_issues_new_after_save(context = {})
      return if skip_webhooks(context)
      issue = context[:issue]
      controller = context[:controller]
      project = issue.project
      webhooks = Webhook.where(:project_id => project.project.id)
      webhooks = Webhook.where(:project_id => 0) unless webhooks && webhooks.length > 0
      return unless webhooks
      post(webhooks, issue_to_json(issue, controller))
    end

    def controller_issues_edit_after_save(context = {})
      return if skip_webhooks(context)
      journal = context[:journal]
      controller = context[:controller]
      issue = context[:issue]
      project = issue.project
      webhooks = Webhook.where(:project_id => project.project.id)
      webhooks = Webhook.where(:project_id => 0) unless webhooks && webhooks.length > 0
      return unless webhooks
      post(webhooks, journal_to_json(issue, journal, controller))
    end

    def controller_issues_bulk_edit_after_save(context = {})
      return if skip_webhooks(context)
      journal = context[:journal]
      controller = context[:controller]
      issue = context[:issue]
      project = issue.project
      webhooks = Webhook.where(:project_id => project.project.id)
      webhooks = Webhook.where(:project_id => 0) unless webhooks && webhooks.length > 0
      return unless webhooks
      post(webhooks, journal_to_json(issue, journal, controller))
    end

    def model_changeset_scan_commit_for_issue_ids_pre_issue_update(context = {})
      issue = context[:issue]
      journal = issue.current_journal
      webhooks = Webhook.where(:project_id => issue.project.project.id)
      webhooks = Webhook.where(:project_id => 0) unless webhooks && webhooks.length > 0
      return unless webhooks
      post(webhooks, journal_to_json(issue, journal, nil))
    end

    private
    def issue_to_json(issue, controller)
      msg = {
        :project_name => issue.project,
        :author => issue.author.to_s,
        :action => "created",
        :issue => issue,
        :mentions => "#{mentions issue.description}"
      }
      card = {}
      card[:header] = {
        :title => "#{msg[:author]} #{msg[:action]} #{escape msg[:issue]} #{msg[:mentions]}",
        :subtitle => "#{escape msg[:project_name]}"
      }
      widgets = [{
        :keyValue => {
          :topLabel => I18n.t("field_status"),
          :content => escape(issue.status.to_s),
          :contentMultiline => "false"
          }
      }, {
        :keyValue => {
          :topLabel => I18n.t("field_priority"),
          :content => escape(issue.priority.to_s),
          :contentMultiline => "false"
        }
      }]

      widgets << {
        :keyValue => {
          :topLabel => I18n.t("field_assigned_to"),
          :content => escape(issue.assigned_to.to_s),
          :contentMultiline => "false"
        }
      } if issue.assigned_to

      card[:sections] = [
        {
          :widgets => widgets
        }
		  ]

      {
        :card => card
        
      }.to_json
#       {
#         :payload => {
#           :action => 'opened',
#           :issue => RedmineWebhook::IssueWrapper.new(issue).to_hash,
#           :url => controller.issue_url(issue)
#         }
#       }.to_json
    end

    def journal_to_json(issue, journal, controller)
      {
        :payload => {
          :action => 'updated',
          :issue => RedmineWebhook::IssueWrapper.new(issue).to_hash,
          :journal => RedmineWebhook::JournalWrapper.new(journal).to_hash,
          :url => controller.nil? ? 'not yet implemented' : controller.issue_url(issue)
        }
      }.to_json
    end
	  
    def mentions text
	return nil if text.nil?
	names = extract_usernames text
	names.present? ? "\nTo: " + names.join(', ') : nil
    end

    def extract_usernames text = ''
	if text.nil?
		text = ''
	end

	# slack usernames may only contain lowercase letters, numbers,
	# dashes and underscores and must start with a letter or number.
	text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
    end
	  
    def escape(msg)
	msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end


    def post(webhooks, request_body)
      cert_store = OpenSSL::X509::Store.new
      cert_store.add_file('ca.pem')
      Thread.start do
        webhooks.each do |webhook|
          begin
            Faraday.post do |req|
              req.url webhook.url
              req.headers['Content-Type'] = 'application/json'
              req.body = request_body
	      req.ssl[:cert_store] = cert_store
            end
          rescue => e
            Rails.logger.error e
          end
        end
      end
    end
  end
end
