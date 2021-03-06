class Api::V1::PartnersController < ApiController
  skip_before_action :verify_authenticity_token
  respond_to :json

  def create
    return head :forbidden unless api_key_valid?

    partner = Partner.where(
      diaper_bank_id: partner_params[:diaper_bank_id],
      diaper_partner_id: partner_params[:diaper_partner_id]
    ).first_or_create

    user = User.invite!(email: partner_params[:email], partner: partner) do |new_user|
      new_user.message = partner_params[:invitation_text]
      new_user.invitation_reply_to = partner_params[:organization_email]
    end

    render json: {
      email: user.email,
      id: partner.id
    }
  rescue ActiveRecord::RecordInvalid => e
    render e.message
  end

  def update
    return head :forbidden unless api_key_valid?

    partner = Partner.find_by!(diaper_partner_id: partner_params[:diaper_partner_id])
    if partner_params[:status] == "pending"
      partner.update(partner_status: "pending")
    elsif partner_params[:status] == "recertification_required"
      partner.update(partner_status: "recertification_required")
      partner.users.each do |user|
        RecertificationMailer.notice_email(user).deliver_later
      end
    elsif partner_params[:status] == "approved"
      partner.update(partner_status: "verified")
    else
      partner.update(partner_status: "pending")
    end

    partner.update(status_in_diaper_base: partner_params[:status])

    render json: { message: "Partner status: #{partner.partner_status}." }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render e.message
  end

  def show
    return head :forbidden unless api_key_valid?

    partner = Partner.find_by(diaper_partner_id: params[:id])

    if params[:impact_metrics]
      render json: { agency: partner.impact_metrics }
    else
      render json: { agency: partner.export_hash }
    end
  end

  private

  def partner_params
    params.require(:partner).permit(
      :diaper_bank_id,
      :diaper_partner_id,
      :invitation_text,
      :organization_email,
      :email,
      :status
    )
  end
end
