import SwiftUI

private struct AIConsentModifier: ViewModifier {
    @Bindable var consent: AIConsent

    func body(content: Content) -> some View {
        content
            .alert("允许将分析内容发送给 DeepSeek？", isPresented: $consent.isPresented) {
                Button("同意并继续", action: consent.approve)
                    .accessibilityIdentifier("approveAIDataSharing")
                Button("暂不使用 AI", role: .cancel, action: consent.decline)
                    .accessibilityIdentifier("declineAIDataSharing")
            } message: {
                Text("根据你使用的功能，本次分析所需的食物描述、所选餐食或烟盒照片、问题，或经你确认的健康汇总，会通过小食痰记服务器转交 DeepSeek，用于识别和生成建议。你可以在通用设置中撤回授权。")
            }
            .onDisappear(perform: consent.cancelPending)
    }
}

extension View {
    func aiDataConsent(_ consent: AIConsent) -> some View {
        modifier(AIConsentModifier(consent: consent))
    }
}
