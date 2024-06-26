use hmac::{Hmac, Mac};
use rand::{rngs::StdRng, Rng, SeedableRng};
use sha3::Sha3_256;
use uuid::{Error, Uuid};

type Hmac256 = Hmac<Sha3_256>;

pub fn generate_flag32() -> Result<String, Error> {
    let mut rng = StdRng::from_entropy();
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    print!("{}", s);
    Ok(s)
}

pub fn generate_hmac(uuid: Uuid, secret: String, taskid: String) -> Result<String, Error> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice).expect("Any size array");
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s);
}

pub fn compare_hmac(hmac: String, uuid: Uuid, secret: String, taskid: String) -> Result<bool, Error> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice).expect("Any size array");
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s == hmac);
}

pub fn generate_uuid() -> Result<Uuid, Error> {
    let id = Uuid::now_v7();
    return Ok(id);
}
