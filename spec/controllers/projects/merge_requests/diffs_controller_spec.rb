# frozen_string_literal: true

require 'spec_helper'

describe Projects::MergeRequests::DiffsController do
  include ProjectForksHelper

  shared_examples 'forked project with submodules' do
    render_views

    let(:project) { create(:project, :repository) }
    let(:forked_project) { fork_project_with_submodules(project) }
    let(:merge_request) { create(:merge_request_with_diffs, source_project: forked_project, source_branch: 'add-submodule-version-bump', target_branch: 'master', target_project: project) }

    before do
      project.add_developer(user)

      merge_request.reload
      go
    end

    it 'renders' do
      expect(response).to be_successful
      expect(response.body).to have_content('Subproject commit')
    end
  end

  shared_examples 'persisted preferred diff view cookie' do
    context 'with view param' do
      before do
        go(view: 'parallel')
      end

      it 'saves the preferred diff view in a cookie' do
        expect(response.cookies['diff_view']).to eq('parallel')
      end
    end

    context 'when the user cannot view the merge request' do
      before do
        project.team.truncate
        go
      end

      it 'returns a 404' do
        expect(response).to have_gitlab_http_status(404)
      end
    end
  end

  let(:project) { create(:project, :repository) }
  let(:user) { create(:user) }
  let(:merge_request) { create(:merge_request_with_diffs, target_project: project, source_project: project) }

  before do
    project.add_maintainer(user)
    sign_in(user)
  end

  describe 'GET show' do
    def go(extra_params = {})
      params = {
        namespace_id: project.namespace.to_param,
        project_id: project,
        id: merge_request.iid,
        format: 'json'
      }

      get :show, params: params.merge(extra_params)
    end

    context 'with default params' do
      context 'for the same project' do
        before do
          allow(controller).to receive(:rendered_for_merge_request?).and_return(true)
        end

        it 'serializes merge request diff collection' do
          expect_any_instance_of(DiffsSerializer).to receive(:represent).with(an_instance_of(Gitlab::Diff::FileCollection::MergeRequestDiff), an_instance_of(Hash))

          go
        end
      end

      context 'when note has no position' do
        before do
          create(:legacy_diff_note_on_merge_request, project: project, noteable: merge_request, position: nil)
        end

        it 'serializes merge request diff collection' do
          expect_any_instance_of(DiffsSerializer).to receive(:represent).with(an_instance_of(Gitlab::Diff::FileCollection::MergeRequestDiff), an_instance_of(Hash))

          go
        end
      end

      it_behaves_like 'forked project with submodules'
    end

    it_behaves_like 'persisted preferred diff view cookie'
  end

  describe 'GET diff_for_path' do
    def diff_for_path(extra_params = {})
      params = {
        namespace_id: project.namespace.to_param,
        project_id: project,
        id: merge_request.iid,
        format: 'json'
      }

      get :diff_for_path, params: params.merge(extra_params)
    end

    let(:existing_path) { 'files/ruby/popen.rb' }

    context 'when the merge request exists' do
      context 'when the user can view the merge request' do
        context 'when the path exists in the diff' do
          it 'enables diff notes' do
            diff_for_path(old_path: existing_path, new_path: existing_path)

            expect(assigns(:diff_notes_disabled)).to be_falsey
            expect(assigns(:new_diff_note_attrs)).to eq(noteable_type: 'MergeRequest',
                                                        noteable_id: merge_request.id,
                                                        commit_id: nil)
          end

          it 'only renders the diffs for the path given' do
            diff_for_path(old_path: existing_path, new_path: existing_path)

            paths = json_response["diff_files"].map { |file| file['new_path'] }

            expect(paths).to include(existing_path)
          end
        end
      end

      context 'when the user cannot view the merge request' do
        before do
          project.team.truncate
          diff_for_path(old_path: existing_path, new_path: existing_path)
        end

        it 'returns a 404' do
          expect(response).to have_gitlab_http_status(404)
        end
      end
    end

    context 'when the merge request does not exist' do
      before do
        diff_for_path(id: merge_request.iid.succ, old_path: existing_path, new_path: existing_path)
      end

      it 'returns a 404' do
        expect(response).to have_gitlab_http_status(404)
      end
    end

    context 'when the merge request belongs to a different project' do
      let(:other_project) { create(:project) }

      before do
        other_project.add_maintainer(user)
        diff_for_path(old_path: existing_path, new_path: existing_path, project_id: other_project)
      end

      it 'returns a 404' do
        expect(response).to have_gitlab_http_status(404)
      end
    end
  end

  describe 'GET diffs_batch' do
    def go(extra_params = {})
      params = {
        namespace_id: project.namespace.to_param,
        project_id: project,
        id: merge_request.iid,
        format: 'json'
      }

      get :diffs_batch, params: params.merge(extra_params)
    end

    context 'when feature is disabled' do
      before do
        stub_feature_flags(diffs_batch_load: false)
      end

      it 'returns 404' do
        go

        expect(response).to have_gitlab_http_status(404)
      end
    end

    context 'when not authorized' do
      let(:other_user) { create(:user) }

      before do
        sign_in(other_user)
      end

      it 'returns 404' do
        go

        expect(response).to have_gitlab_http_status(404)
      end
    end

    context 'with default params' do
      let(:expected_options) do
        {
          merge_request: merge_request,
          pagination_data: {
            current_page: 1,
            next_page: nil,
            total_pages: 1
          }
        }
      end

      it 'serializes paginated merge request diff collection' do
        expect_next_instance_of(PaginatedDiffSerializer) do |instance|
          expect(instance).to receive(:represent)
            .with(an_instance_of(Gitlab::Diff::FileCollection::MergeRequestDiffBatch), expected_options)
            .and_call_original
        end

        go
      end
    end

    context 'with smaller diff batch params' do
      let(:expected_options) do
        {
          merge_request: merge_request,
          pagination_data: {
            current_page: 2,
            next_page: 3,
            total_pages: 4
          }
        }
      end

      it 'serializes paginated merge request diff collection' do
        expect_next_instance_of(PaginatedDiffSerializer) do |instance|
          expect(instance).to receive(:represent)
            .with(an_instance_of(Gitlab::Diff::FileCollection::MergeRequestDiffBatch), expected_options)
            .and_call_original
        end

        go(page: 2, per_page: 5)
      end
    end

    it_behaves_like 'forked project with submodules'
    it_behaves_like 'persisted preferred diff view cookie'
  end
end
