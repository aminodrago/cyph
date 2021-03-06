import {BehaviorSubject, Observable} from 'rxjs';
import {potassiumUtil} from './crypto/potassium/potassium-util';
import {IAsyncValue} from './iasync-value';
import {LockFunction} from './lock-function-type';
import {util} from './util';


/**
 * IAsyncValue implementation that wraps a local value.
 */
export class LocalAsyncValue<T> implements IAsyncValue<T> {
	/** @ignore */
	protected readonly subject: BehaviorSubject<T>	= new BehaviorSubject(this.value);

	/** @inheritDoc */
	public readonly lock: LockFunction	= util.lockFunction();

	/** @inheritDoc */
	public async getValue () : Promise<T> {
		return this.value;
	}

	/** @inheritDoc */
	public async setValue (newValue: T) : Promise<void> {
		if (ArrayBuffer.isView(this.value)) {
			potassiumUtil.clearMemory(this.value);
		}
		else if (this.value instanceof Array) {
			for (const v of this.value) {
				if (ArrayBuffer.isView(v)) {
					potassiumUtil.clearMemory(v);
				}
			}
		}

		this.value	= newValue;
		this.subject.next(this.value);
	}

	/** @inheritDoc */
	public async updateValue (f: (value: T) => Promise<T>) : Promise<void> {
		await this.lock(async () => {
			const value	= await this.getValue();
			let newValue: T;
			try {
				newValue	= await f(value);
			}
			catch {
				return;
			}
			this.setValue(newValue);
		});
	}

	/** @inheritDoc */
	public watch () : Observable<T> {
		return this.subject;
	}

	constructor (
		/** @ignore */
		protected value: T
	) {}
}
