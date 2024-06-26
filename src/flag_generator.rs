use hmac::{Hmac, Mac};
use rand::{rngs::StdRng, Rng, SeedableRng};
use sha3::Sha3_256;
use uuid::{Error, Uuid};

type Hmac256 = Hmac<Sha3_256>;

fn generate_flag32() -> Result<String, Error> {
    let mut rng = StdRng::from_entropy();
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    print!("{}", s);
    Ok(s)
}

fn generate_hmac(uuid: Uuid, secret: String, taskid: String) -> Result<String, Error> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice).expect("Any size array");
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s);
}

fn compare_hmac(hmac: String, uuid: Uuid, secret: String, taskid: String) -> Result<bool, Error> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice).expect("Any size array");
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s == hmac);
}

fn generate_uuid() -> Result<Uuid, Error> {
    let id = Uuid::now_v7();
    return Ok(id);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        assert!(generate_uuid().is_ok());
    }
    #[test]
    fn test_compare_hmac() {
        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let taskid = "task1".to_string();
        let secret2 = "Work".to_string();
        let taskid2 = "task1".to_string();
        let hash = generate_hmac(id, secret, taskid).expect("error");
        print!("{}", hash);
        assert!(compare_hmac(hash, id, secret2, taskid2).expect("should work"))
    }

    #[test]
    fn test_rand() {
        assert!(generate_flag32().is_ok());
    }
}
