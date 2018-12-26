# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/logger'

class TestLogger < Minitest::Test
  describe Sidekiq::Logger do
    let(:logdev) { StringIO.new }

    subject { Sidekiq::Logger.new(logdev) }

    before do
      Thread.current[:sidekiq_context] = nil
      Thread.current[:sidekiq_tid] = nil
    end

    after do
      Thread.current[:sidekiq_context] = nil
      Thread.current[:sidekiq_tid] = nil
    end

    describe 'initialization' do
      describe 'formatter' do
        subject { Sidekiq::Logger.new(logdev).formatter }

        describe 'default formatter' do
          it 'sets pretty formatter' do
            assert_kind_of Sidekiq::Logger::Formatters::Pretty, subject
          end
        end

        describe 'when DYNO env var is present' do
          around do |test|
            ENV['DYNO'] = 'dyno identifier'
            test.call
            ENV['DYNO'] = nil
          end

          it 'sets without timestamp formatter' do
            assert_kind_of Sidekiq::Logger::Formatters::WithoutTimestamp, subject
          end
        end

        describe 'when logger formatter :json' do
          around do |test|
            Sidekiq.stub :logger_formatter, :json do
              test.call
            end
          end

          it 'sets json formatter' do
            assert_kind_of Sidekiq::Logger::Formatters::JSON, subject
          end
        end
      end
    end

    describe '#tid' do
      describe 'default' do
        it 'returns formatted thread id' do
          Thread.current.stub :object_id, 70286338772540 do
            Process.stub :pid, 6363 do
              assert_equal 'owx3jd7mv', subject.tid
            end
          end
        end
      end

      describe 'memoization' do
        before do
          Thread.current[:sidekiq_tid] = 'abcdefjhi'
        end

        it 'current thread :sidekiq_tid attribute reference' do
          Thread.current.stub :object_id, 70286338772540 do
            Process.stub :pid, 6363 do
              assert_equal 'abcdefjhi', subject.tid
            end
          end
        end
      end
    end

    describe '#context' do
      describe 'default' do
        it 'returns empty hash' do
          assert_equal({}, subject.context)
        end
      end

      describe 'memoization' do
        before do
          Thread.current[:sidekiq_context] = { a: 1 }
        end

        it 'returns current thread :sidekiq_context attribute reference' do
          assert_equal({ a: 1 }, subject.context)
        end
      end
    end

    describe '#with_context' do
      it 'adds context to the current thread' do
        assert_equal({}, subject.context)

        subject.with_context(a: 1) do
          assert_equal({ a: 1 }, subject.context)
        end

        assert_equal({}, subject.context)
      end

      describe 'nested contexts' do
        it 'adds multiple contexts to the current thread' do
          assert_equal({}, subject.context)

          subject.with_context(a: 1) do
            assert_equal({ a: 1 }, subject.context)

            subject.with_context(b: 2, c: 3) do
              assert_equal({ a: 1, b: 2, c: 3 }, subject.context)
            end

            assert_equal({ a: 1 }, subject.context)
          end

          assert_equal({}, subject.context)
        end
      end
    end

    describe 'formatters' do
      let(:severity) { 'INFO' }
      let(:utc_time) { Time.utc(2020, 1, 1) }
      let(:prg) { 'sidekiq' }
      let(:msg) { 'Old pond frog jumps in sound of water' }

      around do |test|
        Process.stub :pid, 4710 do
          Sidekiq.logger.stub :tid, 'ouy7z76mx' do
            test.call
          end
        end
      end

      describe 'with context' do
        subject { Sidekiq::Logger::Formatters::Pretty.new.call(severity, utc_time, prg, msg) }

        let(:context) { { class: 'HaikuWorker', bid: nil } }

        around do |test|
          Sidekiq.logger.stub :context, context do
            test.call
          end
        end

        it 'skips context with nil values' do
          assert_equal "2020-01-01T00:00:00.000Z 4710 TID-ouy7z76mx CLASS=HaikuWorker INFO: Old pond frog jumps in sound of water\n", subject
        end
      end

      describe Sidekiq::Logger::Formatters::Pretty do
        describe '#call' do
          subject { Sidekiq::Logger::Formatters::Pretty.new.call(severity, utc_time, prg, msg) }

          it 'formats with timestamp, pid, tid, severity, message' do
            assert_equal "2020-01-01T00:00:00.000Z 4710 TID-ouy7z76mx INFO: Old pond frog jumps in sound of water\n", subject
          end

          describe 'with context' do
            let(:context) { { class: 'HaikuWorker', jid: 'dac39c70844dc0ee3f157ced' } }

            around do |test|
              Sidekiq.logger.stub :context, context do
                test.call
              end
            end

            it 'formats with timestamp, pid, tid, context, severity, message' do
              assert_equal "2020-01-01T00:00:00.000Z 4710 TID-ouy7z76mx CLASS=HaikuWorker JID=dac39c70844dc0ee3f157ced INFO: Old pond frog jumps in sound of water\n", subject
            end
          end
        end
      end

      describe Sidekiq::Logger::Formatters::WithoutTimestamp do
        describe '#call' do
          subject { Sidekiq::Logger::Formatters::WithoutTimestamp.new.call(severity, utc_time, prg, msg) }

          it 'formats with pid, tid, severity, message' do
            assert_equal "4710 TID-ouy7z76mx INFO: Old pond frog jumps in sound of water\n", subject
          end

          describe 'with context' do
            let(:context) { { class: 'HaikuWorker', jid: 'dac39c70844dc0ee3f157ced' } }

            around do |test|
              Sidekiq.logger.stub :context, context do
                test.call
              end
            end

            it 'formats with pid, tid, context, severity, message' do
              assert_equal "4710 TID-ouy7z76mx CLASS=HaikuWorker JID=dac39c70844dc0ee3f157ced INFO: Old pond frog jumps in sound of water\n", subject
            end
          end
        end
      end

      describe Sidekiq::Logger::Formatters::JSON do
        describe '#call' do
          subject { Sidekiq::Logger::Formatters::JSON.new.call(severity, utc_time, prg, msg) }

          it 'formats with pid, tid, severity, message' do
            assert_equal %q|{"ts":"2020-01-01T00:00:00.000Z","pid":4710,"tid":"ouy7z76mx","ctx":{},"sev":"INFO","msg":"Old pond frog jumps in sound of water"}|, subject
          end

          describe 'with context' do
            let(:context) { { class: 'HaikuWorker', jid: 'dac39c70844dc0ee3f157ced' } }

            around do |test|
              Sidekiq.logger.stub :context, context do
                test.call
              end
            end

            it 'formats with pid, tid, context, severity, message' do
              assert_equal %q|{"ts":"2020-01-01T00:00:00.000Z","pid":4710,"tid":"ouy7z76mx","ctx":{"class":"HaikuWorker","jid":"dac39c70844dc0ee3f157ced"},"sev":"INFO","msg":"Old pond frog jumps in sound of water"}|, subject
            end
          end
        end
      end
    end
  end
end