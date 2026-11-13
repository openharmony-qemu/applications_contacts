/* Copyright (c) 2026 Harmony Contrib
 * SPDX-License-Identifier: Apache-2.0 */
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import { common } from '@kit.AbilityKit';
import ability from '@ohos.ability.ability';
import type { UiExtentionParam } from './ContactUiExtentionAbility';
import WorkerWrapper, { WorkerRequestScope } from '../workers/base/WorkerWrapper';

interface PickerSessionStorage {
  uiExtentionSession: UIExtensionContentSession;
  parameters: UiExtentionParam;
  pickerSession: PickerSession;
  isGettingPickerData: boolean;
  isShowBindSheet: boolean;
  isPickerSearch: boolean;
  isShowAccountants: boolean;
  isFromSaveContactPicker: boolean;
  isSaveExistContact: boolean;
}

// No module/global result destination. Every callback retains this exact session.
export default class PickerSession {
  private static sequence: number = 0;
  public readonly id: number = ++PickerSession.sequence;
  public readonly scope: WorkerRequestScope = new WorkerRequestScope();
  public readonly storage: LocalStorage;
  private resultClaimed: boolean = false;
  private closing: boolean = false;
  private pendingResult: ability.AbilityResult | undefined = undefined;
  public readonly session: UIExtensionContentSession;
  public readonly context: common.UIExtensionContext;
  public readonly worker: WorkerWrapper;
  public params: UiExtentionParam;

  constructor(session: UIExtensionContentSession, context: common.UIExtensionContext,
    params: UiExtentionParam, worker: WorkerWrapper) {
    this.session = session;
    this.context = context;
    this.params = params;
    this.worker = worker;
    const initialStorage: PickerSessionStorage = {
      uiExtentionSession: session, parameters: params, pickerSession: this,
      isGettingPickerData: false, isShowBindSheet: false, isPickerSearch: false,
      isShowAccountants: false, isFromSaveContactPicker: params.isSaveContact,
      isSaveExistContact: params.isSaveExistContact
    };
    this.storage = new LocalStorage(initialStorage);
    if (params.contact !== undefined) { this.storage.setOrCreate('contactFromPicker', params.contact); }
  }

  get active(): boolean { return this.scope.active; }

  addCleanup(cleanup: () => void): () => void {
    return this.scope.onDispose(cleanup);
  }

  delay(action: () => void, milliseconds: number): number {
    let remove: () => void = () => {};
    const timer = setTimeout(() => {
      remove();
      if (this.active) { action(); }
    }, milliseconds);
    remove = this.addCleanup(() => clearTimeout(timer));
    return timer;
  }

  dispose(): void {
    this.scope.dispose();
  }

  async finish(result: ability.AbilityResult): Promise<boolean> {
    if (!this.active || this.closing) { return false; }
    this.resultClaimed = true;
    // Retry only the terminal frame, never resend already delivered chunks.
    this.pendingResult = this.pendingResult ?? result;
    this.closing = true;
    try {
      await this.session.terminateSelfWithResult(this.pendingResult);
      this.dispose();
      return true;
    } catch (error) {
      console.error('Contact picker result delivery failed: ' + error?.message);
      return false;
    } finally {
      this.closing = false;
    }
  }

  async deliver(chunks: Record<string, Object>[], result: ability.AbilityResult): Promise<boolean> {
    if (!this.active) { return false; }
    if (this.resultClaimed) {
      return this.pendingResult !== undefined ? this.finish(this.pendingResult) : false;
    }
    this.resultClaimed = true;
    try {
      for (const chunk of chunks) {
        if (!this.active) { return false; }
        this.session.sendData(chunk);
      }
    } catch (error) {
      console.error('Contact picker chunk delivery failed: ' + error?.message);
      return this.finish({ resultCode: -1 });
    }
    return this.finish(result);
  }
}
