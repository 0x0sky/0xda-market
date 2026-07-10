# frozen_string_literal: true

require "digest"
require "monitor"
require_relative "../core/contracts"

module ZeroXDA
  module Market
    module Providers
      class ManualProvider
        class Task
          STATUSES = %w[pending completed rejected].freeze

          attr_reader :id,
                      :order_id,
                      :capability,
                      :payload,
                      :context,
                      :terms,
                      :status,
                      :result,
                      :failure,
                      :created_at,
                      :updated_at

          def initialize(
            id:,
            order_id:,
            capability:,
            payload:,
            context:,
            terms:,
            status: "pending",
            result: nil,
            failure: nil,
            created_at:,
            updated_at: created_at
          )
            raise ArgumentError, "task status is invalid" unless STATUSES.include?(status)

            @id = Core::RecordSupport.identifier(id, field: "task id")
            @order_id = Core::RecordSupport.identifier(order_id, field: "order id")
            @capability = Core::RecordSupport.capability(capability)
            @payload = Core::RecordSupport.document(payload, field: "payload")
            @context = Core::RecordSupport.document(context, field: "context")
            @terms = Core::RecordSupport.document(terms, field: "terms")
            @status = status.dup.freeze
            @result = Core::RecordSupport.optional_document(result, field: "result")
            @failure = Core::RecordSupport.optional_document(failure, field: "failure")
            @created_at = Core::RecordSupport.time(created_at, field: "created_at")
            @updated_at = Core::RecordSupport.time(updated_at, field: "updated_at")
            freeze
          end
        end

        attr_reader :key

        def initialize(key:, clock:, quote_terms: { fulfillment: "manual" }, quote_ttl: nil)
          @key = Core::RecordSupport.identifier(key, field: "provider key")
          @clock = clock
          @quote_terms = Core::RecordSupport.document(quote_terms, field: "quote terms")
          unless quote_ttl.nil? || (quote_ttl.is_a?(Numeric) && quote_ttl.positive?)
            raise ArgumentError, "quote_ttl must be a positive number or nil"
          end

          @quote_ttl = quote_ttl
          @tasks = {}
          @task_ids_by_idempotency_key = {}
          @monitor = Monitor.new
        end

        def quote(intent:)
          now = current_time
          Core::Contracts::QuoteResult.new(
            terms: @quote_terms,
            private_state: { manual_intent_id: intent.id },
            expires_at: @quote_ttl && now + @quote_ttl
          )
        end

        def execute(order:, idempotency_key:)
          task = @monitor.synchronize do
            find_or_create_task(order, idempotency_key)
          end

          case task.status
          when "pending"
            Core::Contracts::PendingResult.new(
              reference: task.id,
              data: { status: "awaiting_operator" }
            )
          when "completed"
            Core::Contracts::ExecutionResult.new(
              reference: task.result.fetch("reference"),
              data: task.result.fetch("data")
            )
          when "rejected"
            raise Core::ProviderFailure.new(
              task.failure.fetch("message"),
              code: task.failure.fetch("code"),
              retryable: task.failure.fetch("retryable"),
              details: task.failure.fetch("details")
            )
          end
        end

        def tasks(status: nil)
          validate_status_filter!(status)
          @monitor.synchronize do
            selected = @tasks.values
            selected = selected.select { |task| task.status == status } if status
            selected.sort_by(&:created_at)
          end
        end

        def find_task(id)
          @monitor.synchronize { @tasks[id.to_s] }
        end

        def fetch_task(id)
          find_task(id) || raise(Core::NotFound.new("manual_task", id))
        end

        def complete_task(id, reference: nil, data: {})
          @monitor.synchronize do
            task = fetch_task(id)
            return task if task.status == "completed"

            ensure_pending!(task, "complete")
            replace_task(
              task,
              status: "completed",
              result: { reference: reference, data: data },
              failure: nil,
              updated_at: current_time
            )
          end
        end

        def reject_task(id, message:, code: "manual_rejection", details: {})
          @monitor.synchronize do
            task = fetch_task(id)
            return task if task.status == "rejected"

            ensure_pending!(task, "reject")
            replace_task(
              task,
              status: "rejected",
              result: nil,
              failure: {
                message: Core::RecordSupport.identifier(message, field: "failure message"),
                code: Core::RecordSupport.identifier(code, field: "failure code"),
                retryable: false,
                details: details
              },
              updated_at: current_time
            )
          end
        end

        private

        def find_or_create_task(order, idempotency_key)
          normalized_key = Core::RecordSupport.identifier(
            idempotency_key,
            field: "idempotency key"
          )
          existing_id = @task_ids_by_idempotency_key[normalized_key]
          return @tasks.fetch(existing_id) if existing_id

          task = Task.new(
            id: task_id_for(normalized_key),
            order_id: order.id,
            capability: order.capability,
            payload: order.payload,
            context: order.context,
            terms: order.terms,
            created_at: current_time
          )
          @tasks[task.id] = task
          @task_ids_by_idempotency_key[normalized_key] = task.id
          task
        end

        def task_id_for(idempotency_key)
          "manual-#{Digest::SHA256.hexdigest(idempotency_key)[0, 32]}"
        end

        def replace_task(task, **changes)
          attributes = {
            id: task.id,
            order_id: task.order_id,
            capability: task.capability,
            payload: task.payload,
            context: task.context,
            terms: task.terms,
            status: task.status,
            result: task.result,
            failure: task.failure,
            created_at: task.created_at,
            updated_at: task.updated_at
          }
          replacement = Task.new(**attributes.merge(changes))
          @tasks[replacement.id] = replacement
        end

        def ensure_pending!(task, event)
          return if task.status == "pending"

          raise Core::InvalidTransition.new(
            resource: "manual_task",
            id: task.id,
            from: task.status,
            event: event
          )
        end

        def validate_status_filter!(status)
          return if status.nil? || Task::STATUSES.include?(status)

          raise ArgumentError, "task status filter is invalid"
        end

        def current_time
          value = @clock.call
          unless value.is_a?(Time)
            raise Core::ProviderContractError.new("clock must return a Time")
          end

          value.getutc
        end
      end
    end
  end
end
